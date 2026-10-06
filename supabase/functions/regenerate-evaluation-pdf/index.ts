// regenerate-evaluation-pdf
//
// Admin-only. Rebuilds the completed-sheet PDF for an evaluation response
// that is already in the database, uploads it, and points pdf_url at it.
// No insert, no email -- it only (re)writes the attachment.
//
// Written 10/6/26 to backfill Clippard Instrument Labs, whose response was
// recovered by hand before public-submit-evaluation generated PDFs at all,
// so its pdf_url was null and the dashboard had nothing to download. Kept
// rather than thrown away because the same need recurs: a response whose
// PDF predates a change to the layout, or one whose PDF/email step hit the
// best-effort guard in the submit function and came back as a warning.
//
// The drawing code is a verbatim copy of public-submit-evaluation v7. If the
// form layout changes there, copy it here too -- the two must agree, or a
// regenerated sheet stops matching the one the client was emailed.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { PDFDocument, StandardFonts, rgb } from "https://esm.sh/pdf-lib@1.17.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

// ------------------------------------------------------------------ PDF
// pdf-lib's standard fonts encode WinAnsi only; one character outside it
// throws. Everything drawn passes through safe() first.
const WINANSI_EXTRA = new Set([0x20AC,0x201A,0x0192,0x201E,0x2026,0x2020,0x2021,0x02C6,0x2030,0x0160,0x2039,0x0152,0x017D,0x2018,0x2019,0x201C,0x201D,0x2022,0x2013,0x2014,0x02DC,0x2122,0x0161,0x203A,0x0153,0x017E,0x0178]);
const SUBS: Record<number, string> = { 0x2713: "", 0x2717: "", 0x2714: "", 0x2718: "", 0x2192: "->", 0x2190: "<-", 0x2197: "", 0x25B8: ">", 0x25BE: "v", 0x00A0: " " };
function safe(t: unknown): string {
  let out = "";
  for (const ch of String(t ?? "")) {
    const c = ch.codePointAt(0)!;
    if (SUBS[c] !== undefined) { out += SUBS[c]; continue; }
    out += (c <= 0xFF || WINANSI_EXTRA.has(c)) ? ch : "?";
  }
  return out;
}

const GREEN_DARK = rgb(0.106, 0.278, 0.173);
const GREEN_MID  = rgb(0.231, 0.455, 0.255);
const GREEN_PALE = rgb(0.906, 0.945, 0.910);
const GREEN_LINE = rgb(0.682, 0.776, 0.667);
const AMBER_BG   = rgb(0.988, 0.957, 0.855);
const AMBER_BAR  = rgb(0.827, 0.671, 0.173);
const GREY_700   = rgb(0.263, 0.302, 0.337);
const GREY_400   = rgb(0.612, 0.639, 0.667);
const BORDER     = rgb(0.804, 0.827, 0.804);
const ROW_ALT    = rgb(0.965, 0.969, 0.961);
const WHITE      = rgb(1, 1, 1);

async function buildEvaluationFormPdf(r: any, logoBytes: Uint8Array | null): Promise<Uint8Array> {
  const doc = await PDFDocument.create();
  const reg  = await doc.embedFont(StandardFonts.Helvetica);
  const bold = await doc.embedFont(StandardFonts.HelveticaBold);
  const obl  = await doc.embedFont(StandardFonts.HelveticaOblique);
  let logo: any = null;
  try { if (logoBytes) logo = await doc.embedPng(logoBytes); } catch (_e) { logo = null; }

  const W = 612, H = 792, M = 42, CW = W - M * 2;
  let page = doc.addPage([W, H]);
  let y = H;
  const nl = () => { page = doc.addPage([W, H]); y = H - M; };
  const need = (n: number) => { if (y - n < M + 24) nl(); };

  const wrap = (t: unknown, font: any, size: number, maxW: number) => {
    const out: string[] = [];
    safe(t).split(/\r?\n/).forEach((par) => {
      let line = "";
      par.split(/\s+/).filter(Boolean).forEach((w) => {
        const nx = line ? line + " " + w : w;
        if (font.widthOfTextAtSize(nx, size) <= maxW) line = nx;
        else { if (line) out.push(line); line = w; }
      });
      out.push(line);
    });
    return out.length ? out : [""];
  };
  const draw = (t: unknown, x: number, yy: number, o: any = {}) =>
    page.drawText(safe(t), { x, y: yy, size: o.size ?? 9.5, font: o.font ?? reg, color: o.color ?? GREY_700 });
  const para = (t: unknown, x: number, maxW: number, o: any = {}) => {
    const size = o.size ?? 9.5, lead = o.lead ?? 1.45;
    wrap(t, o.font ?? reg, size, maxW).forEach((l) => { need(size * lead); draw(l, x, y - size, o); y -= size * lead; });
  };
  const badge = (label: string) => {
    need(26);
    page.drawRectangle({ x: M, y: y - 15, width: 24, height: 15, color: GREEN_DARK });
    draw(label, M + 6, y - 11.5, { font: bold, size: 8.5, color: WHITE });
  };

  if (logo) {
    const lw = 150, lh = (logo.height / logo.width) * lw;
    page.drawImage(logo, { x: M, y: H - 26 - lh, width: lw, height: lh });
    draw("Evaluation Sheet", M + lw + 18, H - 26 - lh / 2 - 5, { font: bold, size: 16, color: GREEN_DARK });
    y = H - 26 - lh - 14;
  } else {
    draw("NATIONAL CENTER FOR", M, H - 34, { font: bold, size: 7.5, color: GREY_400 });
    draw("ECONOMIC GARDENING", M, H - 46, { font: bold, size: 12, color: GREEN_DARK });
    draw("Evaluation Sheet", M + 160, H - 44, { font: bold, size: 16, color: GREEN_DARK });
    y = H - 62;
  }
  page.drawRectangle({ x: 0, y: y - 3, width: W, height: 3, color: AMBER_BAR });
  y -= 10;

  const intro = "It has been a pleasure to work with you and your company in the Economic Gardening program. This evaluation will bring the engagement to a close. Hopefully you found the research valuable and useful in making strategic decisions for growing your company.";
  const introLines = wrap(intro, reg, 8.8, CW - 28);
  const bandH = introLines.length * 8.8 * 1.5 + 34;
  page.drawRectangle({ x: 0, y: y - bandH, width: W, height: bandH, color: GREEN_DARK });
  let by = y - 16;
  introLines.forEach((l) => { draw(l, M + 2, by - 8.8, { size: 8.8, color: rgb(0.886, 0.925, 0.878) }); by -= 8.8 * 1.5; });
  draw("Thank you again for giving us a chance to work with you and your company.  — Your NCEG Team", M + 2, by - 8.8, { font: bold, size: 8.8, color: WHITE });
  y -= bandH + 12;

  const fieldPair = (l1: string, v1: any, l2: string, v2: any) => {
    need(44);
    const colW = (CW - 16) / 2;
    ([[l1, v1, M], [l2, v2, M + colW + 16]] as any[]).forEach(([lab, val, x]) => {
      draw(lab, x, y - 8, { font: bold, size: 7.2, color: GREY_700 });
      page.drawRectangle({ x, y: y - 32, width: colW, height: 19, color: WHITE, borderColor: BORDER, borderWidth: 0.8 });
      draw(wrap(val || "", reg, 9, colW - 12)[0] || "", x + 7, y - 26.5, { size: 9, color: rgb(0.1, 0.1, 0.1) });
    });
    y -= 40;
  };
  page.drawRectangle({ x: 0, y: y - 88, width: W, height: 88, color: GREEN_PALE });
  y -= 8;
  fieldPair("DATE", r.respondent_date, "YOUR NAME & TITLE", r.respondent_name);
  fieldPair("COMPANY", r.company_name, "PROGRAM SPONSOR", r.sponsor_name);
  y -= 10;

  badge("Q1");
  draw("How useful was the research in answering the questions in the controlling document?", M + 32, y - 11.5, { font: bold, size: 10.5, color: GREEN_DARK });
  y -= 24;
  const colQ = CW - 180, cx = [M + colQ, M + colQ + 60, M + colQ + 120], colR = 60;
  need(22);
  page.drawRectangle({ x: M, y: y - 20, width: CW, height: 20, color: GREEN_DARK });
  draw("Research Question", M + 8, y - 13.5, { font: bold, size: 7.8, color: WHITE });
  ["Very Useful", "Partially Useful", "Not Useful"].forEach((h, i) => {
    draw(h, cx[i] + (colR - bold.widthOfTextAtSize(h, 7.2)) / 2, y - 13.5, { font: bold, size: 7.2, color: WHITE });
  });
  y -= 20;
  const ratings = Array.isArray(r.question_ratings) ? r.question_ratings : [];
  ratings.forEach((q: any, i: number) => {
    const lines = wrap(String(i + 1) + ". " + String(q.question || "").replace(/^\s*\d+\.\s*/, ""), reg, 8.4, colQ - 16);
    const rowH = Math.max(lines.length * 8.4 * 1.35 + 12, 26);
    need(rowH);
    if (i % 2 === 1) page.drawRectangle({ x: M, y: y - rowH, width: CW, height: rowH, color: ROW_ALT });
    page.drawLine({ start: { x: M, y: y - rowH }, end: { x: M + CW, y: y - rowH }, thickness: 0.5, color: BORDER });
    let ly = y - 11;
    lines.forEach((l) => { draw(l, M + 8, ly, { size: 8.4, color: rgb(0.1, 0.1, 0.1) }); ly -= 8.4 * 1.35; });
    const mid = y - rowH / 2;
    ["very", "partial", "not"].forEach((v, c) => {
      const ox = cx[c] + colR / 2;
      page.drawCircle({ x: ox, y: mid, size: 5.4, borderColor: q.rating === v ? GREEN_MID : BORDER, borderWidth: q.rating === v ? 1.6 : 1, color: WHITE });
      if (q.rating === v) page.drawCircle({ x: ox, y: mid, size: 2.6, color: GREEN_MID });
    });
    y -= rowH;
  });
  y -= 12;

  draw('PLEASE EXPLAIN ANY "NOT USEFUL" OR "PARTIALLY USEFUL" RESPONSES', M, y - 8, { font: bold, size: 7.2, color: GREY_700 });
  y -= 14;
  const exLines = wrap(r.q1_explain || "", reg, 9, CW - 16);
  const exH = Math.max(exLines.length * 9 * 1.4 + 12, 30);
  need(exH);
  page.drawRectangle({ x: M, y: y - exH, width: CW, height: exH, color: WHITE, borderColor: BORDER, borderWidth: 0.8 });
  let ey = y - 14;
  exLines.forEach((l) => { draw(l, M + 8, ey, { size: 9, color: rgb(0.1, 0.1, 0.1) }); ey -= 9 * 1.4; });
  y -= exH + 14;

  need(50);
  page.drawRectangle({ x: M, y: y - 44, width: CW, height: 44, color: GREEN_PALE, borderColor: GREEN_LINE, borderWidth: 1 });
  draw("SUMMARY OF RATINGS", M + 12, y - 15, { font: bold, size: 8.4, color: GREEN_DARK });
  draw(`Very Useful (3 pts): ${r.very_useful_count ?? 0}      Partially Useful (2 pts): ${r.partially_useful_count ?? 0}      Not Useful (1 pt): ${r.not_useful_count ?? 0}`, M + 12, y - 28, { size: 8.6, color: GREY_700 });
  draw(`Weighted Score: ${r.weighted_score ?? 0} / ${r.weighted_max ?? 0}`, M + 12, y - 39, { font: bold, size: 8.8, color: GREEN_DARK });
  y -= 56;

  badge("Q2");
  draw("Were you adequately prepared for the engagement?", M + 32, y - 11.5, { font: bold, size: 10.5, color: GREEN_DARK });
  y -= 26;
  need(28);
  ([["Yes", "yes"], ["No", "no"]] as any[]).forEach(([lab, v], i) => {
    const bx = M + i * 78, on = r.prepared === v;
    page.drawRectangle({ x: bx, y: y - 22, width: 68, height: 22, color: on ? GREEN_DARK : WHITE, borderColor: on ? GREEN_DARK : BORDER, borderWidth: 1 });
    draw(lab, bx + (68 - bold.widthOfTextAtSize(lab, 9)) / 2, y - 15, { font: bold, size: 9, color: on ? WHITE : GREY_400 });
  });
  y -= 34;

  badge("Q3");
  draw("What could we have done better or differently to better meet your needs?", M + 32, y - 11.5, { font: bold, size: 10.5, color: GREEN_DARK });
  y -= 24;
  const q3 = wrap(r.improvement_suggestions || "", reg, 9, CW - 16);
  const q3H = Math.max(q3.length * 9 * 1.4 + 14, 40);
  need(q3H);
  page.drawRectangle({ x: M, y: y - q3H, width: CW, height: q3H, color: WHITE, borderColor: BORDER, borderWidth: 0.8 });
  let qy = y - 15;
  q3.forEach((l) => { draw(l, M + 8, qy, { size: 9, color: rgb(0.1, 0.1, 0.1) }); qy -= 9 * 1.4; });
  y -= q3H + 16;

  badge("Q4");
  draw("On a scale of 1–10, how likely are you to recommend this program to others?", M + 32, y - 11.5, { font: bold, size: 10.5, color: GREEN_DARK });
  y -= 24;
  need(42);
  draw("Would NOT recommend", M, y - 7, { size: 7, color: GREY_400 });
  const rl = "Would DEFINITELY recommend";
  draw(rl, M + CW - reg.widthOfTextAtSize(rl, 7), y - 7, { size: 7, color: GREY_400 });
  y -= 12;
  const bw = (CW - 9 * 5) / 10;
  for (let i = 1; i <= 10; i++) {
    const bx = M + (i - 1) * (bw + 5), on = Number(r.nps_score) === i;
    page.drawRectangle({ x: bx, y: y - 26, width: bw, height: 26, color: on ? GREEN_DARK : WHITE, borderColor: on ? GREEN_DARK : BORDER, borderWidth: 1 });
    const t = String(i);
    draw(t, bx + (bw - bold.widthOfTextAtSize(t, 9.5)) / 2, y - 17, { font: bold, size: 9.5, color: on ? WHITE : GREY_400 });
  }
  y -= 38;

  badge("Q5");
  para("Please identify any other CEOs or companies who might be interested in or benefit from the NCEG program:", M + 32, CW - 32, { font: bold, size: 10.5, color: GREEN_DARK });
  y -= 6;
  const refs = (Array.isArray(r.referrals) ? r.referrals : []).filter((x: any) => x && (x.name || x.company || x.contact));
  const rc = CW / 3;
  need(20);
  page.drawRectangle({ x: M, y: y - 18, width: CW, height: 18, color: GREEN_DARK });
  ["CEO Name", "Company", "Contact Information"].forEach((h, i) => draw(h, M + i * rc + 8, y - 12.5, { font: bold, size: 7.6, color: WHITE }));
  y -= 18;
  (refs.length ? refs : [{ name: "", company: "", contact: "" }]).forEach((x: any, i: number) => {
    need(20);
    if (i % 2 === 1) page.drawRectangle({ x: M, y: y - 18, width: CW, height: 18, color: ROW_ALT });
    page.drawLine({ start: { x: M, y: y - 18 }, end: { x: M + CW, y: y - 18 }, thickness: 0.5, color: BORDER });
    [x.name, x.company, x.contact].forEach((v: any, c: number) => {
      draw(wrap(v || "", reg, 8.4, rc - 14)[0] || "", M + c * rc + 8, y - 12.5, { size: 8.4, color: v ? rgb(0.1, 0.1, 0.1) : GREY_400 });
    });
    y -= 18;
  });
  y -= 16;

  if (r.testimonial) {
    const tl = wrap(r.testimonial, obl, 9, CW - 40);
    const th = tl.length * 9 * 1.45 + 36;
    need(th);
    page.drawRectangle({ x: M, y: y - th, width: CW, height: th, color: AMBER_BG });
    page.drawRectangle({ x: M, y: y - th, width: 3.5, height: th, color: AMBER_BAR });
    draw("Testimonial", M + 16, y - 15, { font: bold, size: 9, color: rgb(0.42, 0.33, 0.07) });
    let ty = y - 30;
    tl.forEach((l) => { draw(l, M + 16, ty, { font: obl, size: 9, color: rgb(0.2, 0.2, 0.2) }); ty -= 9 * 1.45; });
    y -= th + 10;
  }

  const pages = doc.getPages();
  pages.forEach((pg: any, i: number) => pg.drawText(
    safe(`Submitted ${r.submitted_at ? new Date(r.submitted_at).toLocaleDateString("en-US") : ""}  ·  National Center for Economic Gardening  ·  page ${i + 1} of ${pages.length}`),
    { x: M, y: 24, size: 7.2, font: reg, color: GREY_400 }));
  return await doc.save();
}

async function fetchLogo(): Promise<Uint8Array | null> {
  try {
    const base = (Deno.env.get("PUBLIC_SITE_URL") || "https://egdb.netlify.app").replace(/\/+$/, "");
    const res = await fetch(`${base}/NCEG_Logo_transparent.png`, { signal: AbortSignal.timeout(5000) });
    if (!res.ok) return null;
    return new Uint8Array(await res.arrayBuffer());
  } catch (_e) { return null; }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);

  try {
    const authHeader = req.headers.get("Authorization") || "";
    if (!authHeader) return jsonResponse({ error: "Not signed in." }, 401);

    const url = Deno.env.get("SUPABASE_URL")!;
    const adminClient = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { autoRefreshToken: false, persistSession: false } });
    const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: authHeader } }, auth: { autoRefreshToken: false, persistSession: false } });

    // Admin only. This rewrites a stored record of what a CEO submitted, so
    // it is deliberately narrower than the dashboard's ordinary edit rights.
    const { data: auth } = await userClient.auth.getUser();
    if (!auth?.user) return jsonResponse({ error: "Not signed in." }, 401);
    const { data: me } = await adminClient.from("users").select("role, archived_at").eq("id", auth.user.id).maybeSingle();
    if (!me || me.archived_at || me.role !== "super_admin") return jsonResponse({ error: "Admins only." }, 403);

    const body = await req.json().catch(() => ({}));
    const responseId = (body.responseId || "").trim();
    if (!responseId) return jsonResponse({ error: "Missing responseId." }, 400);

    const { data: r, error: rErr } = await adminClient
      .from("client_evaluation_responses").select("*").eq("id", responseId).maybeSingle();
    if (rErr) return jsonResponse({ error: rErr.message }, 400);
    if (!r) return jsonResponse({ error: "No such evaluation response." }, 404);

    const { data: client } = await adminClient.from("clients").select("name").eq("id", r.client_id).maybeSingle();
    const clientName = client?.name || r.company_name || "Client";

    const pdfBytes = await buildEvaluationFormPdf(r, await fetchLogo());
    const safeCompany = String(clientName).replace(/[^a-zA-Z0-9._-]/g, "_").slice(0, 60);
    const fileName = `NCEG-Evaluation-${safeCompany}.pdf`;
    const path = `submitted/${r.client_id}/${r.id}-${fileName}`;

    const { error: upErr } = await adminClient.storage.from("client-evaluations")
      .upload(path, pdfBytes, { contentType: "application/pdf", upsert: true });
    if (upErr) return jsonResponse({ error: "Upload failed: " + upErr.message }, 500);

    const { data: pub } = adminClient.storage.from("client-evaluations").getPublicUrl(path);
    const { error: updErr } = await adminClient.from("client_evaluation_responses")
      .update({ pdf_url: pub.publicUrl }).eq("id", r.id);
    if (updErr) return jsonResponse({ error: updErr.message }, 500);

    return jsonResponse({ ok: true, pdfUrl: pub.publicUrl, bytes: pdfBytes.length });
  } catch (e) {
    return jsonResponse({ error: e instanceof Error ? e.message : "Unexpected error." }, 500);
  }
});
