// enrich-from-website
//
// Given a company's website URL, this function fetches the homepage
// (server-side -- the browser can't, CORS blocks fetching third-party
// sites) and pulls back three things to pre-fill the Info Wizard's
// "Website & Social Media Links" step and the "Company Description" step:
//
//   1. Social links  -- scanned out of the page's <a href> tags by known
//      host (linkedin/facebook/instagram/x/youtube). Reliable, because
//      these almost always sit in the footer, which is in the static HTML.
//   2. A logo guess  -- apple-touch-icon > og:image > icon, fetched and
//      returned inline as a data: URL so the browser can hand it straight
//      to the existing logo upload. Best-effort: favicons are low-res and
//      og:image is often a banner, so the Team Lead still eyeballs it.
//   3. A draft description -- the homepage (plus /about if found) stripped
//      to text and handed to Claude to write 1-2 plain paragraphs. Works
//      for any company with real copy on its site, regardless of size.
//
// Nothing here touches Supabase data. Auth is only "is this a real signed-
// in user" (same Bearer session + publishable apikey every page sends),
// so a random unauthenticated caller can't use it as a free scraper/LLM.
//
// HOW TO DEPLOY (no CLI needed)
//   1. Supabase Dashboard -> Edge Functions -> Create a new function named
//      exactly  enrich-from-website
//   2. Paste this whole file into its Code tab
//   3. Deploy
//   4. In the function's Settings tab, turn OFF "Verify JWT with legacy
//      secret" (same as eg-dashboard-ai -- this function does its own
//      session check below).
//   SUPABASE_URL is injected automatically. ANTHROPIC_API_KEY is the same
//   secret eg-dashboard-ai already uses -- if that function works, this
//   one has the key too. Without the key, socials + logo still work and
//   the description is simply skipped.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { encodeBase64 } from "https://deno.land/std@0.224.0/encoding/base64.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const CLAUDE_MODEL = "claude-sonnet-5";

const FETCH_UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36";
const PAGE_TIMEOUT_MS = 9000;
const LOGO_TIMEOUT_MS = 7000;
const MAX_LOGO_BYTES = 600_000;
const MAX_TEXT_CHARS = 9000;

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);

  try {
    const authHeader = req.headers.get("Authorization") || "";
    const publishableKey = req.headers.get("apikey") || req.headers.get("Apikey") || "";
    if (!authHeader.startsWith("Bearer ") || !publishableKey) {
      return jsonResponse({ error: "Missing session." }, 401);
    }
    const userClient = createClient(SUPABASE_URL, publishableKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: userErr } = await userClient.auth.getUser();
    if (userErr || !user) {
      return jsonResponse({ error: "Could not verify your session -- sign in again." }, 401);
    }

    const body = await req.json().catch(() => null);
    const rawUrl = typeof body?.url === "string" ? body.url.trim() : "";
    const homepage = normalizeUrl(rawUrl);
    if (!homepage) return jsonResponse({ error: "That doesn't look like a valid website address." }, 400);

    // ---- Fetch the homepage ----
    let finalUrl = homepage;
    let html = "";
    try {
      const res = await fetchWithTimeout(homepage, PAGE_TIMEOUT_MS);
      finalUrl = res.url || homepage;
      if (!res.ok) return jsonResponse({ error: `The website returned ${res.status}.` }, 502);
      html = await res.text();
    } catch (_e) {
      return jsonResponse({ error: "Couldn't reach that website (it timed out or blocked the request)." }, 502);
    }

    const socials = extractSocials(html, finalUrl);
    const logoCandidates = extractLogoCandidates(html, finalUrl);

    // ---- Description: homepage text (+ /about if we can find one) -> Claude ----
    let description: string | null = null;
    if (ANTHROPIC_API_KEY) {
      let text = htmlToText(html);
      const aboutHref = findAboutLink(html, finalUrl);
      if (aboutHref) {
        try {
          const aRes = await fetchWithTimeout(aboutHref, PAGE_TIMEOUT_MS);
          if (aRes.ok) text += "\n\n" + htmlToText(await aRes.text());
        } catch (_e) { /* about page is optional */ }
      }
      text = text.slice(0, MAX_TEXT_CHARS).trim();
      if (text.length > 400) {
        try {
          description = await describeWithClaude(finalUrl, text);
        } catch (e) {
          console.error("describeWithClaude failed:", e);
        }
      }
    }

    // ---- Logo: fetch the top candidate's bytes, return inline ----
    let logo: { dataUrl: string; filename: string } | null = null;
    for (const candidate of logoCandidates) {
      logo = await tryFetchLogo(candidate);
      if (logo) break;
    }

    return jsonResponse({
      website: finalUrl,
      socials,
      logo,
      logoSourceUrl: logo ? undefined : (logoCandidates[0] || null),
      description,
    });
  } catch (err) {
    console.error("enrich-from-website error:", err);
    return jsonResponse({ error: "Something went wrong reading that website." }, 500);
  }
});

// ---------------------------------------------------------------------------

function normalizeUrl(raw: string): string | null {
  if (!raw) return null;
  let s = raw.trim();
  if (!/^https?:\/\//i.test(s)) s = "https://" + s;
  try {
    const u = new URL(s);
    if (u.protocol !== "http:" && u.protocol !== "https:") return null;
    if (!u.hostname.includes(".")) return null;
    return u.origin + (u.pathname === "/" ? "/" : u.pathname);
  } catch {
    return null;
  }
}

async function fetchWithTimeout(url: string, ms: number): Promise<Response> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), ms);
  try {
    return await fetch(url, {
      redirect: "follow",
      signal: ctrl.signal,
      headers: { "User-Agent": FETCH_UA, "Accept": "text/html,*/*" },
    });
  } finally {
    clearTimeout(t);
  }
}

function absolutize(href: string, base: string): string | null {
  try {
    return new URL(href.trim(), base).href;
  } catch {
    return null;
  }
}

// ---- Socials ----------------------------------------------------------------

const SOCIAL_HOSTS: { key: string; test: (h: string) => boolean }[] = [
  { key: "linkedin", test: (h) => /(^|\.)linkedin\.com$/i.test(h) },
  { key: "facebook", test: (h) => /(^|\.)(facebook\.com|fb\.com)$/i.test(h) },
  { key: "instagram", test: (h) => /(^|\.)instagram\.com$/i.test(h) },
  { key: "twitter", test: (h) => /(^|\.)(twitter\.com|x\.com)$/i.test(h) },
  { key: "youtube", test: (h) => /(^|\.)(youtube\.com|youtu\.be)$/i.test(h) },
];

// share/login/widget URLs that mention a social host but aren't the
// company's own profile
const SOCIAL_JUNK = /\/(sharer|share|intent|dialog|plugins|login|signup|oauth|tweet)\b|[?&](url|u|text)=/i;

function extractSocials(html: string, base: string): Record<string, string> {
  const found: Record<string, string> = {};
  const hrefRe = /href\s*=\s*["']([^"']+)["']/gi;
  let m: RegExpExecArray | null;
  while ((m = hrefRe.exec(html)) !== null) {
    const abs = absolutize(m[1], base);
    if (!abs) continue;
    let u: URL;
    try { u = new URL(abs); } catch { continue; }
    if (u.pathname.length <= 1 && !u.search) continue; // bare "linkedin.com/" is not a profile
    if (SOCIAL_JUNK.test(abs)) continue;
    for (const s of SOCIAL_HOSTS) {
      if (found[s.key]) continue;
      if (s.test(u.hostname)) {
        found[s.key] = abs.replace(/[)"'.,\s]+$/, "");
      }
    }
  }
  return found;
}

// ---- Logo -----------------------------------------------------------------

function attr(tag: string, name: string): string | null {
  const m = tag.match(new RegExp(`${name}\\s*=\\s*["']([^"']+)["']`, "i"));
  return m ? m[1] : null;
}

function extractLogoCandidates(html: string, base: string): string[] {
  const out: string[] = [];
  const push = (href: string | null) => {
    if (!href) return;
    const abs = absolutize(href, base);
    if (abs && !out.includes(abs)) out.push(abs);
  };

  for (const tag of html.match(/<link\b[^>]*>/gi) || []) {
    const rel = (attr(tag, "rel") || "").toLowerCase();
    if (rel.includes("apple-touch-icon")) push(attr(tag, "href"));
  }
  for (const tag of html.match(/<meta\b[^>]*>/gi) || []) {
    const prop = (attr(tag, "property") || attr(tag, "name") || "").toLowerCase();
    if (prop === "og:image" || prop === "og:image:secure_url" || prop === "twitter:image") {
      push(attr(tag, "content"));
    }
  }
  for (const tag of html.match(/<link\b[^>]*>/gi) || []) {
    const rel = (attr(tag, "rel") || "").toLowerCase();
    if (rel === "icon" || rel === "shortcut icon" || rel === "mask-icon") push(attr(tag, "href"));
  }
  return out;
}

async function tryFetchLogo(url: string): Promise<{ dataUrl: string; filename: string } | null> {
  try {
    const res = await fetchWithTimeout(url, LOGO_TIMEOUT_MS);
    if (!res.ok) return null;
    const ct = (res.headers.get("content-type") || "").split(";")[0].trim().toLowerCase();
    if (!ct.startsWith("image/") && ct !== "application/octet-stream") return null;
    const buf = new Uint8Array(await res.arrayBuffer());
    if (!buf.length || buf.length > MAX_LOGO_BYTES) return null;
    const type = ct.startsWith("image/") ? ct : guessImageType(url);
    let filename = "logo";
    try {
      const p = new URL(url).pathname.split("/").pop() || "";
      if (p && /\.[a-z0-9]{2,4}$/i.test(p)) filename = p;
    } catch { /* keep default */ }
    return { dataUrl: `data:${type};base64,${encodeBase64(buf)}`, filename };
  } catch {
    return null;
  }
}

function guessImageType(url: string): string {
  const ext = (url.split("?")[0].split(".").pop() || "").toLowerCase();
  return ({
    png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", gif: "image/gif",
    svg: "image/svg+xml", webp: "image/webp", ico: "image/x-icon",
  } as Record<string, string>)[ext] || "image/png";
}

// ---- Description ---------------------------------------------------------

function htmlToText(html: string): string {
  return html
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, " ")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, " ")
    .replace(/<!--[\s\S]*?-->/g, " ")
    .replace(/<(?:br|\/p|\/div|\/li|\/h[1-6])\s*\/?>/gi, "\n")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&#39;|&rsquo;|&lsquo;/gi, "'")
    .replace(/&quot;|&ldquo;|&rdquo;/gi, '"')
    .replace(/&mdash;/gi, "--")
    .replace(/&[a-z]+;/gi, " ")
    .replace(/[ \t]+/g, " ")
    .replace(/\n\s*\n\s*\n+/g, "\n\n")
    .trim();
}

function findAboutLink(html: string, base: string): string | null {
  const hrefRe = /href\s*=\s*["']([^"']+)["']/gi;
  let m: RegExpExecArray | null;
  while ((m = hrefRe.exec(html)) !== null) {
    const href = m[1];
    if (!/about|company|who-we-are|our-story/i.test(href)) continue;
    const abs = absolutize(href, base);
    if (!abs) continue;
    try {
      const u = new URL(abs);
      const home = new URL(base);
      if (u.hostname !== home.hostname) continue; // stay on-site
      if (/\.(pdf|jpg|png|zip)$/i.test(u.pathname)) continue;
      return abs;
    } catch { /* skip */ }
  }
  return null;
}

async function describeWithClaude(url: string, text: string): Promise<string | null> {
  const system =
    "You write concise company descriptions for an internal consulting dashboard. " +
    "You are given plain text scraped from a company's own website. Write a 1-2 short " +
    "paragraph description of what the company does, who it serves, and any notable " +
    "differentiators (certifications, scale, history, distribution) that are STATED in " +
    "the text. Plain prose -- no headings, no bullet lists, no marketing superlatives. " +
    "Never invent specifics (founding years, employee counts, certifications, customer " +
    "names, revenue) that are not present in the text. If the text is too thin to " +
    "describe the company, reply with exactly: INSUFFICIENT";

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": ANTHROPIC_API_KEY!,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: CLAUDE_MODEL,
      max_tokens: 500,
      system,
      messages: [{ role: "user", content: `Company website: ${url}\n\nScraped text:\n${text}` }],
    }),
  });
  if (!res.ok) {
    console.error("Claude API error:", res.status, await res.text());
    return null;
  }
  const data = await res.json();
  const out = (data?.content || []).find((b: any) => b.type === "text")?.text?.trim() || "";
  if (!out || /^INSUFFICIENT\b/i.test(out)) return null;
  return out;
}
