// engagement-project-kit
//
// Greg (10/12/26): "What would be a good strategy for a simple one click
// button that could help me setup a dedicated project for my work for FE. I
// would want the Discovery Document, the Controlling Document, the
// Application, the Company Info and any research documents already uploaded
// to be in my project files so that i could start with my DM question having
// all the information available in the project."
//
// WHAT THIS IS, AND WHAT IT DELIBERATELY IS NOT
// There is no API that creates a Claude Project, a ChatGPT Project or a
// Gemini Gem, and none that uploads into one. So this does not create the
// project. It assembles the kit -- one zip the specialist unpacks and drags
// in once. Greg (10/12/26): "that way it is LLM agnostic if different
// specialists want to use different LLM projects." Nothing in the output
// names a vendor; the brief ships as Markdown AND as PDF so whichever tool
// the specialist prefers can read it.
//
// MOST OF WHAT WAS ASKED FOR IS NOT A FILE
// The Application is 64 columns in a table. Company Info is a row plus the
// Lists. The Discovery Call Notes are text in client_content. The Controlling
// Document response is jsonb. Exporting those as six separate PDFs would be
// worse than useless -- so they are rendered into ONE briefing document,
// ordered the way a model reads well, with the caller's own research question
// first. Only genuinely uploaded files travel as files.
//
// WHO MAY CALL IT
// A super admin, or someone actually assigned to this engagement. Proved
// here, server side, with the caller's own token -- the button on the page
// is courtesy.
//
// AND, FOR NOW, ONLY GREG
// Greg (10/12/26): "Just make the Project Kit viewable by me." While this is
// being tried out, BETA_EMAILS below is the outer gate. The page hides the
// button from everyone else; this is what makes that true rather than
// decorative. Opening it up means deleting BETA_EMAILS and its check here
// AND the matching list in client_control_center.html -- the two have to move
// together or the button appears and then refuses.
//
// HOW TO DEPLOY (no CLI, no Terminal)
//   1. Supabase Dashboard -> Edge Functions -> New Function, named exactly
//      engagement-project-kit
//   2. Paste this whole file in, Deploy
//   No new secrets. SUPABASE_URL, SUPABASE_ANON_KEY and
//   SUPABASE_SERVICE_ROLE_KEY are provided to every Edge Function.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { PDFDocument, StandardFonts, rgb } from "https://esm.sh/pdf-lib@1.17.1";
import JSZip from "https://esm.sh/jszip@3.10.1";

// Beta gate -- see the header. Delete this and its one check below when the
// kit opens up to every specialist.
const BETA_EMAILS = new Set([
  "greg@leadforcesolutions.com",
  "greg.gotcher@leadforcesolutions.com",
]);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// ---------------------------------------------------------------- labels
const SPECIALTY_LABELS: Record<string, string> = {
  team_lead: "Team Lead",
  market_research: "Market Research",
  digital_marketing: "Digital Marketing",
  gis: "GIS",
  watering_holes: "Watering Holes",
  admin: "Admin",
  quality_control: "Quality Control",
};
// Only these are numbered when an engagement carries more than one, matching
// Team & Hours (Chris, 10/10/26: every work area spelled out).
const NUMBERED_SPECIALTIES = new Set(["market_research", "digital_marketing", "gis", "watering_holes"]);

const AREA_LABELS: Record<string, string> = {
  market_dynamics: "Market Dynamics Research",
  outbound: "Outbound Marketing",
  inbound: "Inbound Marketing",
  watering_holes: "Watering Holes",
  gis: "GIS",
};

const PROJECT_STATUS_LABELS: Record<string, string> = {
  accepted: "Accepted", in_progress: "In Progress", on_hold: "On Hold", closed: "Closed",
};

const RANK_LABELS: Record<string, string> = {
  A: "Rank A - most important",
  B: "Rank B",
  C: "Rank C - least important",
};

function slotLabel(specialty: string, slot: number | null, countInSpecialty: number): string {
  const base = SPECIALTY_LABELS[specialty] || specialty;
  if (!NUMBERED_SPECIALTIES.has(specialty) || countInSpecialty < 2) return base;
  return `${base} ${slot ?? 1}`;
}

function fmtDate(value: unknown): string {
  if (!value) return "";
  const d = new Date(String(value));
  if (isNaN(d.getTime())) return String(value);
  return d.toLocaleDateString("en-US", { year: "numeric", month: "long", day: "numeric", timeZone: "UTC" });
}

function fmtMoney(value: unknown): string {
  if (value === null || value === undefined || value === "") return "";
  const n = Number(value);
  if (!isFinite(n)) return String(value);
  return "$" + n.toLocaleString("en-US");
}

// clients.address is text; client_applications.address is jsonb with
// street/city/state/postal. Either can be the only one filled in.
function fmtAddress(value: unknown): string {
  if (!value) return "";
  if (typeof value === "string") return value;
  if (typeof value === "object") {
    const a = value as Record<string, unknown>;
    const line = [a.street, a.city].filter(Boolean).join(", ");
    const tail = [a.state, a.postal].filter(Boolean).join(" ");
    return [line, tail].filter(Boolean).join(" ");
  }
  return String(value);
}

function slugify(name: string): string {
  return (name || "engagement").replace(/[^A-Za-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "engagement";
}

function safeFilename(name: string): string {
  return (name || "file").replace(/[^A-Za-z0-9._-]/g, "_");
}

// A storage path is stamped with Date.now() on upload so two files of the
// same name can coexist. The stamp is plumbing; strip it for the zip.
function displayFileName(path: string, fallback?: string | null): string {
  const base = (path.split("/").pop() || "").replace(/^\d{10,}-/, "");
  return safeFilename(base || fallback || "file");
}

// ----------------------------------------------------------------- blocks
// The brief is built once as a list of blocks, then rendered twice -- to
// Markdown and to PDF. Two renderers over one source, so the two copies of
// the brief can never drift apart.
type Block =
  | { t: "h1"; text: string }
  | { t: "h2"; text: string }
  | { t: "h3"; text: string }
  | { t: "p"; text: string }
  | { t: "quote"; text: string }
  | { t: "bullets"; items: string[] }
  | { t: "kv"; pairs: [string, string][] }
  | { t: "rule" };

// Several fields are typed one item per line (top business issues, the
// discovery participants). A single newline is not a break in Markdown, so
// rendering them as a paragraph runs them together -- they become bullets.
function pushTextOrList(blocks: Block[], text: unknown) {
  const value = String(text ?? "").trim();
  if (!value) return;
  const lines = value.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
  if (lines.length > 1 && lines.every((l) => l.length < 120)) blocks.push({ t: "bullets", items: lines });
  else blocks.push({ t: "p", text: value });
}

function pushKv(blocks: Block[], pairs: [string, unknown][]) {
  const kept = pairs
    .map(([k, v]) => [k, v === null || v === undefined ? "" : String(v).trim()] as [string, string])
    .filter(([, v]) => v !== "");
  if (kept.length) blocks.push({ t: "kv", pairs: kept });
}

function mdEscape(text: string): string {
  // The brief is read by a model far more often than by a person, so this
  // only neutralises what would silently restructure the document.
  return text.replace(/^(#{1,6})\s/gm, "\\$1 ");
}

function renderMarkdown(blocks: Block[]): string {
  const out: string[] = [];
  for (const b of blocks) {
    switch (b.t) {
      case "h1": out.push(`# ${b.text}`, ""); break;
      case "h2": out.push(`## ${b.text}`, ""); break;
      case "h3": out.push(`### ${b.text}`, ""); break;
      case "p": out.push(mdEscape(b.text), ""); break;
      case "quote": out.push(mdEscape(b.text).split("\n").map((l) => `> ${l}`).join("\n"), ""); break;
      case "bullets": out.push(...b.items.map((i) => `- ${mdEscape(i)}`), ""); break;
      case "kv": out.push(...b.pairs.map(([k, v]) => `- **${k}:** ${mdEscape(v)}`), ""); break;
      case "rule": out.push("---", ""); break;
    }
  }
  return out.join("\n").replace(/\n{3,}/g, "\n\n").trim() + "\n";
}

// pdf-lib's standard fonts encode WinAnsi only; one character outside it
// throws. Everything drawn passes through safe() first. (Same guard
// public-submit-evaluation uses -- keep them in step.)
const WINANSI_EXTRA = new Set([0x20AC,0x201A,0x0192,0x201E,0x2026,0x2020,0x2021,0x02C6,0x2030,0x0160,0x2039,0x0152,0x017D,0x2018,0x2019,0x201C,0x201D,0x2022,0x2013,0x2014,0x02DC,0x2122,0x0161,0x203A,0x0153,0x017E,0x0178]);
const SUBS: Record<number, string> = { 0x2713: "", 0x2717: "", 0x2192: "->", 0x2190: "<-", 0x25B8: ">", 0x25BE: "v", 0x00A0: " " };
function safe(t: unknown): string {
  let out = "";
  for (const ch of String(t ?? "")) {
    const c = ch.codePointAt(0)!;
    if (SUBS[c] !== undefined) { out += SUBS[c]; continue; }
    if (c <= 0xFF || WINANSI_EXTRA.has(c)) { out += ch; continue; }
    out += "?";
  }
  return out;
}

async function renderPdf(blocks: Block[], title: string): Promise<Uint8Array> {
  const pdf = await PDFDocument.create();
  const body = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const italic = await pdf.embedFont(StandardFonts.HelveticaOblique);

  const W = 612, H = 792, M = 54;
  const ink = rgb(0.11, 0.15, 0.21);
  const muted = rgb(0.42, 0.46, 0.51);
  const rule = rgb(0.85, 0.87, 0.89);

  let page = pdf.addPage([W, H]);
  let y = H - M;

  const newPage = () => { page = pdf.addPage([W, H]); y = H - M; };
  const need = (h: number) => { if (y - h < M) newPage(); };

  const wrap = (text: string, font: typeof body, size: number, width: number): string[] => {
    const lines: string[] = [];
    for (const paragraph of safe(text).split("\n")) {
      const words = paragraph.split(/\s+/).filter(Boolean);
      if (!words.length) { lines.push(""); continue; }
      let line = "";
      for (const w of words) {
        const trial = line ? line + " " + w : w;
        if (font.widthOfTextAtSize(trial, size) <= width) { line = trial; continue; }
        if (line) lines.push(line);
        // A single word wider than the column (a long URL) is cut rather
        // than allowed to run off the page edge.
        let rest = w;
        while (font.widthOfTextAtSize(rest, size) > width && rest.length > 1) {
          let cut = rest.length;
          while (cut > 1 && font.widthOfTextAtSize(rest.slice(0, cut), size) > width) cut--;
          lines.push(rest.slice(0, cut));
          rest = rest.slice(cut);
        }
        line = rest;
      }
      if (line) lines.push(line);
    }
    return lines;
  };

  const draw = (text: string, opts: { font?: typeof body; size?: number; color?: typeof ink; indent?: number; gap?: number }) => {
    const font = opts.font ?? body;
    const size = opts.size ?? 10.5;
    const color = opts.color ?? ink;
    const indent = opts.indent ?? 0;
    const lead = size * 1.38;
    for (const line of wrap(text, font, size, W - M * 2 - indent)) {
      need(lead);
      if (line) page.drawText(line, { x: M + indent, y: y - size, size, font, color });
      y -= lead;
    }
    y -= opts.gap ?? 4;
  };

  for (const b of blocks) {
    switch (b.t) {
      case "h1":
        need(40);
        draw(b.text, { font: bold, size: 20, gap: 10 });
        break;
      case "h2":
        need(34);
        y -= 8;
        draw(b.text, { font: bold, size: 14, gap: 6 });
        break;
      case "h3":
        need(26);
        y -= 4;
        draw(b.text, { font: bold, size: 11.5, gap: 4 });
        break;
      case "p":
        draw(b.text, { gap: 7 });
        break;
      case "quote":
        draw(b.text, { font: italic, color: muted, indent: 14, gap: 7 });
        break;
      case "bullets":
        for (const item of b.items) draw("- " + item, { indent: 10, gap: 1 });
        y -= 6;
        break;
      case "kv":
        for (const [k, v] of b.pairs) {
          const label = safe(k) + ": ";
          const labelWidth = bold.widthOfTextAtSize(label, 10.5);
          need(15);
          page.drawText(label, { x: M, y: y - 10.5, size: 10.5, font: bold, color: ink });
          const lines = wrap(v, body, 10.5, W - M * 2 - labelWidth);
          lines.forEach((line, i) => {
            if (i > 0) { y -= 14.5; need(15); }
            page.drawText(line, { x: i === 0 ? M + labelWidth : M + 10, y: y - 10.5, size: 10.5, font: body, color: ink });
          });
          y -= 15;
        }
        y -= 5;
        break;
      case "rule":
        need(18);
        y -= 6;
        page.drawLine({ start: { x: M, y }, end: { x: W - M, y }, thickness: 0.75, color: rule });
        y -= 12;
        break;
    }
  }

  // Footer on every page, drawn last so pagination is already settled.
  const pages = pdf.getPages();
  pages.forEach((p, i) => {
    const note = safe(`${title}  -  page ${i + 1} of ${pages.length}  -  confidential client material`);
    p.drawText(note, { x: M, y: 30, size: 8, font: body, color: muted });
  });

  return await pdf.save();
}

// ------------------------------------------------------------------ brief
type Ctx = {
  client: any;
  content: any;
  application: any;
  program: any;
  questions: any[];
  controlling: any;
  contacts: any[];
  team: any[];
  docs: any[];
  callerId: string;
  callerName: string;
  callerRole: string;
};

// Only a question the team actually numbered gets a number. An unnumbered
// one is named by its area instead -- inventing a number for it collides
// with a real one and makes two questions look like the same question.
function questionHeading(q: any): string {
  if (q.question_number) return `Question ${q.question_number}`;
  const area = AREA_LABELS[q.research_area] || q.research_area;
  return area ? `${area} question` : "Research question";
}

function buildBrief(ctx: Ctx): Block[] {
  const { client, content, application: app, program, questions, controlling, contacts, team, docs } = ctx;
  const b: Block[] = [];

  b.push({ t: "h1", text: `${client.name} - Engagement Brief` });
  b.push({
    t: "p",
    text: `Prepared for ${ctx.callerName}${ctx.callerRole ? ` (${ctx.callerRole})` : ""} on ${fmtDate(new Date().toISOString())}. ` +
      `Confidential client material from the Economic Gardening engagement; it is working context, not a client deliverable.`,
  });
  b.push({ t: "rule" });

  // ---- the caller's own assignment, first -----------------------------
  const mine = questions.filter((q) => q.assigned_user_id === ctx.callerId);
  const others = questions.filter((q) => q.assigned_user_id !== ctx.callerId);

  const renderQuestion = (q: any, heading: string) => {
    b.push({ t: "h3", text: heading });
    b.push({ t: "p", text: q.question || "(no question text)" });
    const meta: [string, unknown][] = [
      ["Research area", AREA_LABELS[q.research_area] || q.research_area],
      ["Assigned to", q.assignee_name],
      ["Client's ranking", q.ranking ? (RANK_LABELS[q.ranking] || q.ranking) : ""],
      ["Due", fmtDate(q.due_date)],
      ["Completed", fmtDate(q.completed_at)],
    ];
    pushKv(b, meta);
    if (q.background) { b.push({ t: "p", text: "Background from the team: " + q.background }); }
    if (q.customer_notes) { b.push({ t: "p", text: "What the client said about it:" }); b.push({ t: "quote", text: q.customer_notes }); }
  };

  if (mine.length) {
    b.push({ t: "h2", text: "Your research question" + (mine.length > 1 ? "s" : "") });
    b.push({
      t: "p",
      text: "This is the work you own on this engagement. Everything below it is context for answering it.",
    });
    mine.forEach((q) => renderQuestion(q, questionHeading(q)));
    b.push({ t: "rule" });
  }

  // ---- company ---------------------------------------------------------
  b.push({ t: "h2", text: "The company" });
  pushKv(b, [
    ["Company", client.name],
    ["Program", program?.name],
    ["Address", fmtAddress(client.address) || fmtAddress(app?.address)],
    ["County", client.county],
    ["Website", client.website_url || app?.website],
    ["NAICS", client.naics_codes || app?.naics_code],
    ["Founded", app?.year_founded],
    ["Phone", app?.phone],
    ["Engagement status", PROJECT_STATUS_LABELS[client.project_status] || client.project_status],
    ["Accepted", fmtDate(client.date_accepted)],
    ["Discovery call", fmtDate(client.discovery_call_at)],
    ["Research due", fmtDate(client.research_due_date)],
  ]);
  if (client.description) { b.push({ t: "h3", text: "What they do" }); b.push({ t: "p", text: client.description }); }

  const issues = client.top_business_issues || app?.top_business_issues;
  if (issues) { b.push({ t: "h3", text: "Top business issues" }); pushTextOrList(b, issues); }

  const socials: string[] = [];
  const addSocial = (label: string, url: unknown) => { if (url) socials.push(`${label}: ${url}`); };
  addSocial("LinkedIn", client.linkedin_url || app?.social_linkedin_url);
  addSocial("Facebook", client.facebook_url || app?.social_facebook_url);
  addSocial("Instagram", client.instagram_url || app?.social_instagram_url);
  addSocial("X / Twitter", client.twitter_url || app?.social_twitter_url);
  addSocial("YouTube", client.youtube_url || app?.social_youtube_url);
  addSocial("Other", client.other_social_url || app?.social_other_url);
  if (socials.length) { b.push({ t: "h3", text: "Web presence" }); b.push({ t: "bullets", items: socials }); }

  // ---- application ------------------------------------------------------
  if (app) {
    b.push({ t: "h2", text: "From the application" });
    b.push({
      t: "p",
      text: "Figures the company reported when it applied to the program. Treat them as self-reported and roughly current, not audited.",
    });
    const revenue: string[] = [];
    for (const year of [2022, 2023, 2024, 2025]) {
      const v = fmtMoney(app[`revenue_${year}`]);
      if (v) revenue.push(`${year}: ${v}`);
    }
    if (revenue.length) { b.push({ t: "h3", text: "Revenue" }); b.push({ t: "bullets", items: revenue }); }

    const fte: string[] = [];
    for (const year of [2022, 2023, 2024, 2025]) {
      const v = app[`fte_${year}`];
      if (v !== null && v !== undefined && v !== "") fte.push(`${year}: ${v}`);
    }
    if (fte.length) { b.push({ t: "h3", text: "Full-time employees" }); b.push({ t: "bullets", items: fte }); }

    const flags: string[] = [];
    if (app.woman_owned) flags.push("Woman-owned");
    if (app.minority_owned) flags.push("Minority-owned");
    if (app.veteran_owned) flags.push("Veteran-owned");
    if (app.disabled_owned) flags.push("Disabled-owned");
    if (app.is_rural) flags.push("Rural");
    if (app.is_private) flags.push("Privately held");
    pushKv(b, [
      ["Designations", flags.join(", ")],
      ["Sales primarily outside the region", app.sales_primarily_external === null ? "" : (app.sales_primarily_external ? "Yes" : "No")],
      ["Employees in state", app.pct_employees_in_state ? app.pct_employees_in_state + "%" : ""],
    ]);

    const officers: string[] = [];
    const addOfficer = (name: unknown, title: unknown, email: unknown, phone: unknown, temperament: unknown) => {
      if (!name) return;
      const bits = [title, email, phone].filter(Boolean).join(" - ");
      officers.push(`${name}${bits ? ` - ${bits}` : ""}${temperament ? ` (temperament: ${temperament})` : ""}`);
    };
    addOfficer(app.primary_officer_name, app.primary_officer_title, app.primary_officer_email, app.primary_officer_phone, app.primary_officer_temperament);
    addOfficer(app.secondary_officer_name, app.secondary_officer_title, app.secondary_officer_email, app.secondary_officer_phone, app.secondary_officer_temperament);
    addOfficer(app.tertiary_officer_name, app.tertiary_officer_title, app.tertiary_officer_email, app.tertiary_officer_phone, null);
    if (officers.length) { b.push({ t: "h3", text: "Officers" }); b.push({ t: "bullets", items: officers }); }
  }

  // ---- discovery call ---------------------------------------------------
  if (content && (content.discovery_call_notes || content.discovery_call_date || content.discovery_business_issues || content.discovery_company_description)) {
    b.push({ t: "h2", text: "Discovery call" });
    pushKv(b, [
      ["Date", fmtDate(content.discovery_call_date)],
      ["Team Lead", content.discovery_team_lead],
      ["Participants", content.discovery_company_contacts || content.discovery_call_participants],
      ["Program Manager", content.discovery_program_manager],
    ]);
    if (content.discovery_company_description) { b.push({ t: "h3", text: "Company description" }); b.push({ t: "p", text: content.discovery_company_description }); }
    if (content.discovery_business_issues) { b.push({ t: "h3", text: "Business issues" }); b.push({ t: "p", text: content.discovery_business_issues }); }
    if (content.discovery_digital_presence) { b.push({ t: "h3", text: "Digital presence" }); b.push({ t: "p", text: content.discovery_digital_presence }); }
    if (content.discovery_call_notes) { b.push({ t: "h3", text: "Notes" }); b.push({ t: "p", text: content.discovery_call_notes }); }
  }

  // ---- all research questions -------------------------------------------
  if (others.length) {
    b.push({ t: "h2", text: mine.length ? "The rest of the engagement's questions" : "Research questions" });
    if (mine.length) {
      b.push({ t: "p", text: "Someone else owns these. They are here so your answer lands beside theirs rather than across them." });
    }
    others.forEach((q) => renderQuestion(q, questionHeading(q)));
  }

  // ---- controlling document response ------------------------------------
  if (controlling) {
    b.push({ t: "h2", text: "Controlling Document - what the client sent back" });
    pushKv(b, [
      ["Submitted", fmtDate(controlling.submitted_at)],
      ["By", controlling.respondent_name || controlling.respondent_email],
    ]);
    const rows = Array.isArray(controlling.question_responses) ? controlling.question_responses : [];
    const items = rows
      .filter((r: any) => r && (r.question || r.ranking || r.notes))
      .map((r: any) => {
        const rank = r.ranking ? (RANK_LABELS[r.ranking] || r.ranking) : "no ranking";
        return `${r.question || "(no question text)"} - ${rank}${r.notes ? ` - "${r.notes}"` : ""}`;
      });
    if (items.length) b.push({ t: "bullets", items });
    if (controlling.overall_notes) { b.push({ t: "h3", text: "Overall notes" }); b.push({ t: "quote", text: controlling.overall_notes }); }
  }

  // ---- lists -------------------------------------------------------------
  const listRows: string[] = [];
  const addList = (label: string, path: unknown, url: unknown) => {
    if (path) listRows.push(`${label}: in this kit, under files/`);
    else if (url) listRows.push(`${label}: ${url}`);
  };
  if (content) {
    addList("Competitors", content.competitor_list_storage_path, content.competitor_list_url);
    addList("Top Customers", content.customer_list_storage_path, content.customer_list_url);
    addList("Keywords", content.keyword_list_storage_path, content.keyword_list_url);
    addList((content.other_list_label || "Other").trim(), content.other_list_storage_path, content.other_list_url);
  }
  if (listRows.length) {
    b.push({ t: "h2", text: "Lists" });
    b.push({ t: "bullets", items: listRows });
  }

  // ---- people --------------------------------------------------------------
  if (contacts.length) {
    b.push({ t: "h2", text: "Company contacts" });
    b.push({
      t: "bullets",
      items: contacts.map((c: any) => [c.name, c.title, c.email, c.phone].filter(Boolean).join(" - ")),
    });
  }
  if (team.length) {
    b.push({ t: "h2", text: "Economic Gardening team" });
    b.push({
      t: "bullets",
      items: team.map((t: any) => `${t.name} - ${t.role}${t.email ? ` - ${t.email}` : ""}`),
    });
  }

  // ---- what travelled as a file ---------------------------------------------
  if (docs.length) {
    b.push({ t: "h2", text: "Files in this kit" });
    b.push({ t: "bullets", items: docs.map((d: any) => `${d.zipName} - ${d.label}`) });
  }

  return b;
}

function buildInstructions(ctx: Ctx): string {
  const mine = ctx.questions.filter((q) => q.assigned_user_id === ctx.callerId);
  const lines: string[] = [];
  lines.push(`# Project instructions - ${ctx.client.name}`);
  lines.push("");
  lines.push("Paste this into your project's custom-instructions or system-prompt box. It is written for any assistant, not a particular one.");
  lines.push("");
  lines.push("---");
  lines.push("");
  lines.push(`You are helping ${ctx.callerName} on an Economic Gardening engagement with ${ctx.client.name}` +
    `${ctx.program?.name ? `, run through ${ctx.program.name}` : ""}.`);
  lines.push("");
  if (ctx.callerRole) lines.push(`My role on this engagement is ${ctx.callerRole}.`);
  if (mine.length) {
    lines.push("");
    lines.push(mine.length > 1 ? "The research questions I own are:" : "The research question I own is:");
    mine.forEach((q) => {
      const rank = q.ranking ? ` The client ranked it ${q.ranking}.` : "";
      lines.push(`- ${q.question}${rank}`);
    });
  }
  lines.push("");
  lines.push("The engagement brief in this project's files carries the company, the application figures, the discovery call, every research question and what the client said about each. Read it before answering. Other files are the documents the team has produced or collected so far.");
  lines.push("");
  lines.push("How to work with me:");
  lines.push("- Economic Gardening serves second-stage growth companies. The deliverable is intelligence the owner can act on, not a general market report.");
  lines.push("- Ground every claim in a source. Say plainly when something is your inference, and when you do not know.");
  lines.push("- Prefer specifics - named companies, real numbers, working links - over summaries of a category.");
  lines.push("- This is confidential client material. Do not reproduce it outside this work.");
  lines.push("");
  return lines.join("\n");
}

function buildReadme(ctx: Ctx, fileNames: string[]): string {
  return [
    `${ctx.client.name} - project kit`,
    `Assembled ${fmtDate(new Date().toISOString())} for ${ctx.callerName}.`,
    "",
    "WHAT THIS IS",
    "Everything the Economic Gardening team holds on this engagement, packed so you can",
    "drop it into a project in whichever assistant you use. Nothing here is specific to one",
    "vendor: the brief ships as Markdown and as PDF, and the instructions are plain text.",
    "",
    "SETTING IT UP (about a minute)",
    "  1. Make a new project and name it after the engagement.",
    "  2. Drag everything in this folder into the project's files or knowledge.",
    "  3. Open project-instructions.md and paste it into the project's custom",
    "     instructions or system prompt.",
    "  4. Start asking.",
    "",
    "Upload either engagement-brief.md or engagement-brief.pdf, not both -- they are the",
    "same document. Markdown reads most cleanly; the PDF is there for tools that will not",
    "take Markdown.",
    "",
    "WHEN NEW RESEARCH LANDS",
    "Click the button again. The kit is dated, so a newer one never overwrites an older one",
    "by accident -- drop the new files in and delete the ones they replace.",
    "",
    "CONFIDENTIAL",
    "This is client material, including self-reported financials. Treat the project you put",
    "it in the way you would treat the engagement itself.",
    "",
    "IN THIS KIT",
    ...fileNames.map((n) => "  - " + n),
    "",
  ].join("\n");
}

// ------------------------------------------------------------------ serve
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);

  try {
    const authHeader = req.headers.get("Authorization") ?? "";

    // Acts AS the caller -- used only to establish who is asking.
    const callerClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: userData, error: userErr } = await callerClient.auth.getUser();
    if (userErr || !userData?.user) return jsonResponse({ error: "Not signed in." }, 401);

    const { data: caller, error: callerErr } = await callerClient
      .from("users").select("id, full_name, role, email, archived_at").eq("id", userData.user.id).single();
    if (callerErr || !caller) return jsonResponse({ error: "Couldn't read your profile." }, 403);
    if (caller.archived_at) return jsonResponse({ error: "This account has been archived." }, 403);

    const body = await req.json().catch(() => ({}));
    const clientId = body.client_id;
    if (!clientId) return jsonResponse({ error: "client_id is required." }, 400);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // The kit carries the client's financials, so who may take one is proved
    // here rather than trusted from the page: a super admin, or someone
    // actually on this engagement.
    const { data: myAssignments } = await admin
      .from("client_assignments").select("specialty_type, slot_number, is_team_lead")
      .eq("client_id", clientId).eq("user_id", caller.id);
    const isSuperAdmin = caller.role === "super_admin";
    if (!isSuperAdmin && !(myAssignments && myAssignments.length)) {
      return jsonResponse({ error: "You're not on this engagement." }, 403);
    }
    // The beta gate (see the header). Super Admin is too wide to stand in for
    // "Greg" -- Chris and Rita hold it too.
    if (!BETA_EMAILS.has((caller.email || "").trim().toLowerCase())) {
      return jsonResponse({ error: "The Project Kit is still being tested. Ask Greg if you'd like it turned on." }, 403);
    }

    const [clientRes, contentRes, appRes, questionRes, controllingRes, contactRes, teamRes, docRes] = await Promise.all([
      admin.from("clients").select("*").eq("id", clientId).single(),
      admin.from("client_content").select("*").eq("client_id", clientId).maybeSingle(),
      admin.from("client_applications").select("*").eq("client_id", clientId).maybeSingle(),
      admin.from("client_research_questions").select("*").eq("client_id", clientId)
        .order("question_number", { ascending: true, nullsFirst: false })
        .order("sort_order", { ascending: true }),
      admin.from("client_controlling_doc_responses").select("*").eq("client_id", clientId)
        .order("submitted_at", { ascending: false }).limit(1).maybeSingle(),
      admin.from("client_contacts").select("*").eq("client_id", clientId),
      admin.from("client_assignments").select("user_id, specialty_type, slot_number, is_team_lead").eq("client_id", clientId),
      admin.from("documents").select("*").eq("client_id", clientId).order("sort_order", { ascending: true }),
    ]);

    if (clientRes.error || !clientRes.data) return jsonResponse({ error: "Engagement not found." }, 404);
    const client = clientRes.data;
    const content = contentRes.data;
    const application = appRes.data;

    const { data: program } = client.econ_dev_company_id
      ? await admin.from("econ_dev_companies").select("name, code").eq("id", client.econ_dev_company_id).maybeSingle()
      : { data: null };

    // One lookup for every person named anywhere in the kit.
    const assignments = teamRes.data || [];
    const userIds = new Set<string>();
    assignments.forEach((a: any) => a.user_id && userIds.add(a.user_id));
    (questionRes.data || []).forEach((q: any) => q.assigned_user_id && userIds.add(q.assigned_user_id));
    const { data: people } = userIds.size
      ? await admin.from("users").select("id, full_name, email").in("id", [...userIds])
      : { data: [] };
    const peopleById = new Map((people || []).map((p: any) => [p.id, p]));

    const countBySpecialty = new Map<string, number>();
    assignments.forEach((a: any) => countBySpecialty.set(a.specialty_type, (countBySpecialty.get(a.specialty_type) || 0) + 1));

    // Admin and Quality Control are backstage on this engagement the same way
    // they are on the client dashboard -- they are not who you go to with a
    // research question.
    const team = assignments
      // An unfilled slot still counts for numbering above, but there is
      // nobody to name. Admin and Quality Control are backstage.
      .filter((a: any) => a.user_id)
      .filter((a: any) => !["admin", "quality_control"].includes(a.specialty_type))
      .map((a: any) => ({
        name: peopleById.get(a.user_id)?.full_name || "(unnamed)",
        email: peopleById.get(a.user_id)?.email || "",
        role: slotLabel(a.specialty_type, a.slot_number, countBySpecialty.get(a.specialty_type) || 1),
        specialty: a.specialty_type,
        slot: a.slot_number ?? 1,
      }))
      .sort((x: any, y: any) => (x.specialty === "team_lead" ? -1 : y.specialty === "team_lead" ? 1 : x.role.localeCompare(y.role)));

    const questions = (questionRes.data || [])
      .filter((q: any) => (q.question || "").trim())
      .map((q: any) => ({ ...q, assignee_name: peopleById.get(q.assigned_user_id)?.full_name || "" }));

    const myRole = (myAssignments || [])
      .map((a: any) => slotLabel(a.specialty_type, a.slot_number, countBySpecialty.get(a.specialty_type) || 1))
      .join(", ");

    const ctx: Ctx = {
      client, content, application, program,
      questions,
      controlling: controllingRes.data,
      contacts: contactRes.data || [],
      team,
      docs: [],
      callerId: caller.id,
      callerName: caller.full_name || "the specialist",
      callerRole: myRole || (isSuperAdmin ? "Admin" : ""),
    };

    // ---- gather the real files ------------------------------------------
    // Every slot that holds an uploaded file, plus the research documents.
    // A slot holding a LINK is named in the brief instead; there is nothing
    // to pack.
    type Pending = { path: string; label: string; folder: string; fallback?: string };
    const pending: Pending[] = [];
    const addPath = (path: unknown, label: string, folder: string, fallback?: string) => {
      if (typeof path === "string" && path) pending.push({ path, label, folder, fallback });
    };
    if (content) {
      addPath(content.discovery_doc_storage_path, "Discovery Document", "files", "discovery-document");
      addPath(content.discovery_notes_storage_path, "Discovery Call Notes", "files", "discovery-call-notes");
      addPath(content.controlling_doc_storage_path, "Controlling Document", "files", "controlling-document");
      addPath(content.research_review_storage_path, "Debriefing", "files", "debriefing");
      addPath(content.closeout_survey_storage_path, "Evaluation Sheet", "files", "evaluation-sheet");
      addPath(content.competitor_list_storage_path, "Competitors list", "files/lists", "competitors");
      addPath(content.customer_list_storage_path, "Top Customers list", "files/lists", "top-customers");
      addPath(content.keyword_list_storage_path, "Keywords list", "files/lists", "keywords");
      addPath(content.other_list_storage_path, `${(content.other_list_label || "Other").trim()} list`, "files/lists", "other");
    }
    for (const d of docRes.data || []) {
      if (!d.storage_path) continue;
      const area = d.research_area ? (AREA_LABELS[d.research_area] || d.research_area) : "Research";
      addPath(d.storage_path, `${area} - ${d.display_name || d.file_name || "document"}`, "files/research", d.file_name);
    }

    const zip = new JSZip();
    const packed: { zipName: string; label: string }[] = [];
    const skipped: string[] = [];
    const usedNames = new Set<string>();

    // One download at a time rather than Promise.all: a kit with twenty
    // research documents should not open twenty concurrent reads against
    // storage, and the whole thing still finishes in seconds.
    for (const item of pending) {
      const { data: blob, error } = await admin.storage.from("client-documents").download(item.path);
      if (error || !blob) { skipped.push(`${item.label} (couldn't be read from storage)`); continue; }
      let name = displayFileName(item.path, item.fallback);
      let full = `${item.folder}/${name}`;
      // Two uploads can share a name; the zip must not lose one of them.
      let n = 2;
      while (usedNames.has(full)) {
        const dot = name.lastIndexOf(".");
        const stem = dot === -1 ? name : name.slice(0, dot);
        const ext = dot === -1 ? "" : name.slice(dot);
        full = `${item.folder}/${stem}-${n}${ext}`;
        n++;
      }
      usedNames.add(full);
      zip.file(full, new Uint8Array(await blob.arrayBuffer()));
      packed.push({ zipName: full, label: item.label });
    }

    ctx.docs = packed;

    const blocks = buildBrief(ctx);
    if (skipped.length) {
      blocks.push({ t: "h2", text: "Not in this kit" });
      blocks.push({ t: "p", text: "These exist on the engagement but could not be packed. Open them from the dashboard instead." });
      blocks.push({ t: "bullets", items: skipped });
    }

    const title = `${client.name} - Engagement Brief`;
    zip.file("engagement-brief.md", renderMarkdown(blocks));
    zip.file("engagement-brief.pdf", await renderPdf(blocks, title));
    zip.file("project-instructions.md", buildInstructions(ctx));
    zip.file("README.txt", buildReadme(ctx, [
      "engagement-brief.md",
      "engagement-brief.pdf",
      "project-instructions.md",
      ...packed.map((p) => p.zipName),
    ]));

    const bytes = await zip.generateAsync({ type: "uint8array", compression: "DEFLATE" });
    const stamp = new Date().toISOString().slice(0, 10);
    const filename = `${slugify(client.name)}-project-kit-${stamp}.zip`;

    return new Response(bytes, {
      status: 200,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/zip",
        "Content-Disposition": `attachment; filename="${filename}"`,
        // The page reads these to name the download and report what it got.
        "X-Kit-Filename": filename,
        "Access-Control-Expose-Headers": "Content-Disposition, X-Kit-Filename, X-Kit-Files, X-Kit-Skipped",
        "X-Kit-Files": String(packed.length),
        "X-Kit-Skipped": String(skipped.length),
      },
    });
  } catch (err) {
    console.error("engagement-project-kit failed", err);
    return jsonResponse({ error: (err as Error)?.message || "Something went wrong building the kit." }, 500);
  }
});
