// extract-controlling-questions
//
// Pulls the research questions out of a Controlling Document that was
// written in Word, so they land in the EGDB form instead of being retyped.
//
// Greg (10 Nov 26): "the word version of controlling documents has headings
// that say Market Research, Inbound, Outbound and Watering Holes. the goal
// of this exercise is to be able to extract the questions and background
// information separately under each of those headings so that the
// specialists can see their questions in the Add Research page."
//
// WHY A MODEL AND NOT A PARSER
//   "there are many versions of the CD template, some use question numbers
//   and some do not." A regex parser has to be right about numbering,
//   heading spelling and where a background block starts; against a dozen
//   template variants it is wrong often enough to be worse than typing.
//
// WHY ITS OWN FUNCTION, NOT A BRANCH OF eg-dashboard-ai
//   That function carries the Ask AI feature, its own admin gate and six
//   read-only database tools. This needs none of it and must not be able to
//   break it. ANTHROPIC_API_KEY is a project-level secret, so a second
//   function reads the same key with nothing to configure.
//
// WHAT IT DOES NOT DO
//   No Priority A/B/C, no customer notes (Greg, 10 Nov 26: "that will be
//   handled outside the software if at all"). No database writes of any
//   kind -- it returns rows for the Team Lead to look at, and the ordinary
//   Save on the Controlling Document page is what stores them.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Matches eg-dashboard-ai. Update both if Anthropic renames the slug.
const CLAUDE_MODEL = "claude-sonnet-5";
const MAX_INPUT_CHARS = 60000;

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// The four areas on the form, with the headings Word documents actually use.
// "Market Research" is the one that matters: every Word template says that,
// and the column behind it is market_dynamics. Left unmapped, the largest
// group of questions in the document would arrive with nowhere to go.
const AREA_GUIDE = `
market_dynamics  - "Market Research", "Market Dynamics", "Market Dynamics Research", "Markets"
outbound         - "Outbound", "Outbound Marketing", "Outbound Sales"
inbound          - "Inbound", "Inbound Marketing", "Website", "SEO"
watering_holes   - "Watering Holes", "Watering Hole Research"
`.trim();

const SYSTEM_PROMPT = `You pull research questions out of a National Center for Economic Gardening "Controlling Document" that was written in Microsoft Word, so they can be loaded into the NCEG Dashboard.

The document is organised under headings. Map each heading to one of these four areas:

${AREA_GUIDE}

For every research question you find, return:
- research_area: one of market_dynamics, outbound, inbound, watering_holes
- question: the research question itself, in the document's own words
- background: the supporting context for that question. It is usually a block labelled "Background", but may simply be the paragraphs under the question. Empty string if there is none.
- question_number: the number shown in the document (1-9) if there is one, otherwise null. Many templates have no numbers; do not invent them.
- heading_seen: the heading text exactly as it appears in the document
- confidence: "high" when the heading clearly matches one of the four areas and the question is unambiguous; "low" when you had to guess either

Rules:
- Quote the document. Do not rewrite, summarise, shorten or improve wording, and do not correct its grammar.
- Extract only questions. Ignore priority or ranking (A/B/C), client comments, feedback, sign-off blocks, headers, footers and page numbers.
- If a heading does not match any of the four areas, still return its questions, with your best-guess research_area and confidence "low".
- If you find nothing that reads as a research question, return an empty list rather than guessing.
- Typical documents hold 4-7 questions in total and no more than 2 under a heading. Many more than that means you are probably picking up prose; be stricter.

Reply with JSON only, no commentary, in exactly this shape:
{"questions":[{"research_area":"market_dynamics","question":"...","background":"...","question_number":1,"heading_seen":"Market Research","confidence":"high"}],"note":"anything the Team Lead should check, or an empty string"}`;

const VALID_AREAS = ["market_dynamics", "outbound", "inbound", "watering_holes"];

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);

  try {
    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!anthropicKey) {
      return jsonResponse({ error: "ANTHROPIC_API_KEY is not set on this project, so extraction is unavailable." }, 500);
    }

    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const authHeader = req.headers.get("Authorization") ?? "";
    const publishableKey = req.headers.get("apikey") ?? "";
    if (!authHeader || !publishableKey) {
      return jsonResponse({ error: "Not signed in." }, 401);
    }

    // Who is asking. Anyone with a staff profile may extract: this returns
    // nothing from the database, so the thing being guarded is the API key,
    // not engagement data. The Save that follows is governed by the same RLS
    // as every other write on the page.
    const userClient = createClient(SUPABASE_URL, publishableKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: userErr } = await userClient.auth.getUser();
    if (userErr || !user) {
      return jsonResponse({ error: "Could not verify your session -- try signing in again." }, 401);
    }
    const { data: profile } = await userClient
      .from("users").select("id, archived_at").eq("id", user.id).single();
    if (!profile || profile.archived_at) {
      return jsonResponse({ error: "This account cannot extract questions." }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const text = String(body.text || "").trim();
    if (!text) {
      return jsonResponse({ error: "Paste the text of the Controlling Document first." }, 400);
    }
    if (text.length > MAX_INPUT_CHARS) {
      return jsonResponse({
        error: `That is ${text.length.toLocaleString()} characters, and the limit is ${MAX_INPUT_CHARS.toLocaleString()}. Paste just the question sections rather than the whole document.`,
      }, 400);
    }

    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": anthropicKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: CLAUDE_MODEL,
        max_tokens: 4000,
        system: SYSTEM_PROMPT,
        messages: [{ role: "user", content: text }],
      }),
    });

    if (!res.ok) {
      const detail = await res.text().catch(() => "");
      return jsonResponse({ error: `The extractor could not be reached (${res.status}). ${detail.slice(0, 300)}` }, 502);
    }

    const payload = await res.json();
    const raw = (payload?.content || [])
      .filter((b: { type: string }) => b.type === "text")
      .map((b: { text: string }) => b.text).join("").trim();

    // Models sometimes wrap JSON in a fenced block even when told not to.
    const cleaned = raw.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "").trim();
    let parsed: { questions?: unknown[]; note?: string };
    try {
      parsed = JSON.parse(cleaned);
    } catch {
      return jsonResponse({ error: "The extractor replied in a shape this page could not read. Try again, or paste a smaller section." }, 502);
    }

    // Everything past this point is defensive: the rows go straight into a
    // form a person then saves, so a bad field should arrive blank rather
    // than as whatever the model happened to emit.
    const questions = (Array.isArray(parsed.questions) ? parsed.questions : [])
      .map((q) => {
        const r = q as Record<string, unknown>;
        const area = String(r.research_area || "");
        const num = Number(r.question_number);
        return {
          research_area: VALID_AREAS.includes(area) ? area : "",
          question: String(r.question || "").trim(),
          background: String(r.background || "").trim(),
          question_number: Number.isInteger(num) && num >= 1 && num <= 9 ? num : null,
          heading_seen: String(r.heading_seen || "").trim(),
          confidence: r.confidence === "low" ? "low" : "high",
        };
      })
      // A row with no question text is nothing to put on the form.
      .filter((q) => q.question);

    return jsonResponse({
      questions,
      note: String(parsed.note || "").trim(),
      model: CLAUDE_MODEL,
    });
  } catch (e) {
    return jsonResponse({ error: e instanceof Error ? e.message : "Unexpected error." }, 500);
  }
});
