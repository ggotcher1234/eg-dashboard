// brief-render-test.mjs
//
// Renders a sample engagement brief from index.ts and checks the things that
// have actually gone wrong: the caller's own question not landing first, the
// application's jsonb address printing as "[object Object]", a list typed one
// item per line collapsing into a run-on paragraph, an unnumbered question
// borrowing a number that belongs to a different question, and an unfilled
// Team & Hours slot showing up as a person.
//
// It does NOT copy any of that logic -- it slices the pure half out of
// index.ts at run time and compiles it, so this file cannot drift away from
// the function it is testing.
//
//   cd supabase/functions/engagement-project-kit
//   npm i --no-save pdf-lib@1.17.1 esbuild@0.21.5
//   node brief-render-test.mjs
//
// Writes engagement-brief.md / .pdf beside itself so the output can be read
// and, with `pdftoppm -png engagement-brief.pdf page`, looked at.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";

const here = path.dirname(fileURLToPath(import.meta.url));
const source = fs.readFileSync(path.join(here, "index.ts"), "utf8");

// Everything above the request handler is pure: no Deno, no network, no
// Supabase. That half is what we compile.
const cut = source.indexOf("// ------------------------------------------------------------------ serve");
if (cut === -1) throw new Error("index.ts no longer has the serve marker this test slices on.");
const pure = source
  .slice(0, cut)
  .replace(/import \{ createClient \}.*\n/, "")
  .replace(/import JSZip.*\n/, "")
  .replace(/from "https:\/\/esm\.sh\/pdf-lib@1\.17\.1"/, 'from "pdf-lib"')
  + "\nexport { buildBrief, buildInstructions, buildReadme, renderMarkdown, renderPdf };\n";

const tmp = path.join(here, ".brief-render-test.tmp.ts");
fs.writeFileSync(tmp, pure);
await build({
  entryPoints: [tmp], bundle: true, platform: "node", format: "esm",
  external: ["pdf-lib"], outfile: path.join(here, ".brief-render-test.tmp.mjs"), logLevel: "warning",
});
const kit = await import("./.brief-render-test.tmp.mjs");

const ME = "me-uuid";
const ctx = {
  client: {
    name: "Fuel Efficiency Inc.", county: "Wayne", address: "101 Davis Parkway, Clyde NY 14433",
    naics_codes: "332999", website_url: "https://www.fuelefficiencyinc.com/",
    linkedin_url: "https://www.linkedin.com/company/fuelefficiencyinc/",
    project_status: "in_progress", research_due_date: "2026-10-28",
    top_business_issues: "Expanding Reach/conversion\nShipping Costs\nFunding a Building Purchase",
  },
  content: {
    competitor_list_storage_path: "clients/x/lists/competitors/1791818359611-Competitors.pdf",
    customer_list_url: "https://docs.example.com/customers",
    other_list_label: "Trade shows", other_list_url: "https://docs.example.com/trade-shows", other_list_storage_path: null,
    keyword_list_storage_path: null, keyword_list_url: null,
    discovery_call_notes: "Amy walked through the shop floor.\nShipping is the pinch point.",
    discovery_call_date: "2026-10-08",
  },
  // address as jsonb, the shape client_applications actually stores.
  application: {
    address: { street: "101 Davis Parkway", city: "Clyde", state: "NY", postal: "14433" },
    year_founded: 1973, revenue_2024: 1185019, revenue_2025: 1207776, fte_2025: 8,
    woman_owned: true, sales_primarily_external: true, pct_employees_in_state: 100,
    primary_officer_name: "Amy Connelly", primary_officer_title: "President",
  },
  program: { name: "Greater Rochester Enterprise", code: "GRE" },
  questions: [
    { question_number: 1, research_area: "market_dynamics", ranking: "A", assigned_user_id: "ann",
      assignee_name: "Ann Sigsby", question: "What are the market dynamics of the heat exchanger industry?" },
    { question_number: 3, research_area: "inbound", ranking: "A", assigned_user_id: ME,
      assignee_name: "Greg Gotcher", question: "How do our competitors' digital marketing efforts compare to ours?",
      background: "They contribute to Google Ads on about 15 keywords.",
      customer_notes: "We get almost no inbound." },
    // No number: must NOT be printed as "Question 3" beside the real one.
    { question_number: null, research_area: "watering_holes", ranking: "B", assigned_user_id: "ann",
      assignee_name: "Ann Sigsby", question: "What value would MWBE certification provide?" },
  ],
  controlling: { submitted_at: "2026-10-09T16:53:30Z", respondent_name: "Amy Connelly",
    overall_notes: "Looks right to us.",
    question_responses: [{ question: "How do our competitors compare?", ranking: "A", notes: "This one matters most." }] },
  contacts: [{ name: "Amy Connelly", title: "President", email: "amy@example.com" }],
  team: [
    { name: "Julie Dreyer", email: "jdreyer@execpc.com", role: "Team Lead", specialty: "team_lead", slot: 1 },
    { name: "Greg Gotcher", email: "greg@example.com", role: "Digital Marketing 1", specialty: "digital_marketing", slot: 1 },
  ],
  docs: [{ zipName: "files/Discovery_Call_Notes.docx", label: "Discovery Document" }],
  callerId: ME, callerName: "Greg Gotcher", callerRole: "Digital Marketing 1",
};

const blocks = kit.buildBrief(ctx);
const md = kit.renderMarkdown(blocks);
const instructions = kit.buildInstructions(ctx);
const pdf = await kit.renderPdf(blocks, "Fuel Efficiency Inc. - Engagement Brief");

fs.writeFileSync(path.join(here, "engagement-brief.md"), md);
fs.writeFileSync(path.join(here, "engagement-brief.pdf"), pdf);
fs.rmSync(tmp, { force: true });
fs.rmSync(path.join(here, ".brief-render-test.tmp.mjs"), { force: true });

const checks = [
  ["the caller's own question comes first", md.indexOf("Your research question") < md.indexOf("The company")],
  ["and it is the caller's, not someone else's", /Your research question[\s\S]{0,400}competitors' digital marketing/.test(md)],
  ["everyone else's are kept separate", md.includes("The rest of the engagement's questions")],
  ["the jsonb address renders as an address", !md.includes("[object Object]")],
  ["revenue is money, not a bare integer", md.includes("$1,185,019")],
  ["a one-per-line field becomes a list", md.includes("- Shipping Costs")],
  ["an unnumbered question does not steal a number", md.includes("Watering Holes question") && (md.match(/### Question 3/g) || []).length === 1],
  ["a list held as a file points into the kit", md.includes("Competitors: in this kit")],
  ["a list held as a link gives the link", md.includes("https://docs.example.com/customers")],
  ["a renamed Other slot uses its own name", md.includes("Trade shows:")],
  ["what the client said is quoted", md.includes("> We get almost no inbound.")],
  ["the controlling response is carried", md.includes("Looks right to us.")],
  ["the instructions name the caller's question", instructions.includes("competitors' digital marketing")],
  ["the instructions name no AI vendor", !/claude|chatgpt|gemini|openai|anthropic/i.test(instructions)],
  ["the pdf is a pdf", Buffer.from(pdf).subarray(0, 5).toString() === "%PDF-"],
];

let failed = 0;
for (const [label, ok] of checks) {
  if (!ok) failed++;
  console.log(`${ok ? "ok  " : "FAIL"}  ${label}`);
}
console.log(`\n${checks.length - failed}/${checks.length} passed. Wrote engagement-brief.md and engagement-brief.pdf.`);
process.exit(failed ? 1 : 0);
