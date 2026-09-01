// public-submit-controlling-doc
//
// The Edge Function a client's Controlling Document review link
// (controlling_document_public.html?client=<id>) submits to. There's no
// Supabase session behind that page -- a client just opens the link, ranks
// each research question, leaves notes/changes, hits Submit -- so this
// function is the entire write path, same "no session to attach the write
// to" model as public-submit-evaluation (078) and public-submit-application
// (066): validate what came in, then write with the service-role client
// (never the anon key).
//
// On success it:
//   1. inserts one client_controlling_doc_responses row -- the immutable
//      record of exactly what the client sent (question_responses jsonb).
//      That insert fires notify_controlling_doc_finalized() (103), which
//      drops an in-app bell notification telling the team the Controlling
//      Document was finalized by the client.
//   2. writes each entry's ranking / notes back onto the matching
//      client_research_questions row (ranking / customer_notes columns), so
//      the internal Controlling Document form reflects the client's input.
//
// Auth model: the page sends the project's anon key as the
// Authorization/apikey headers (enough for Supabase's platform-level "is
// this a validly signed request" check). This function does NOT require a
// signed-in user -- anyone with the link can submit, same as the public
// application and evaluation forms.
//
// HOW TO DEPLOY (no CLI, no Terminal)
//   1. Supabase Dashboard -> Edge Functions -> New Function -> name it
//      "public-submit-controlling-doc"
//   2. Paste this whole file in, Deploy
//   No secrets needed. SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are
//   available to every Edge Function automatically.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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

// Bounds on the free-text fields -- this endpoint has no authenticated
// caller to trust, so nothing from the request body is written through
// unbounded.
const MAX_TEXT = 5000;
function clampText(v: unknown): string | null {
  if (v === undefined || v === null) return null;
  const s = String(v).trim();
  if (!s) return null;
  return s.slice(0, MAX_TEXT);
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function cleanUuid(v: unknown): string | null {
  const s = typeof v === "string" ? v.trim() : "";
  return UUID_RE.test(s) ? s : null;
}
function cleanRanking(v: unknown): string | null {
  const s = typeof v === "string" ? v.trim().toUpperCase() : "";
  return ["A", "B", "C"].includes(s) ? s : null;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  try {
    const body = await req.json().catch(() => ({}));
    const clientId = cleanUuid(body.clientId);
    const data = body.data || {};

    if (!clientId) {
      return jsonResponse({ error: "Missing or invalid client." }, 400);
    }

    const rawResponses = Array.isArray(data.questionResponses) ? data.questionResponses : [];
    if (!rawResponses.length) {
      return jsonResponse({ error: "Nothing to submit." }, 400);
    }

    const cleanResponses = rawResponses
      .map((r: any) => ({
        question_id: cleanUuid(r && r.questionId),
        question: clampText(r && r.question) || "",
        ranking: cleanRanking(r && r.ranking),
        notes: clampText(r && r.notes),
      }))
      .filter((r: any) => r.question_id || r.question || r.ranking || r.notes);

    if (!cleanResponses.length) {
      return jsonResponse({ error: "Nothing to submit." }, 400);
    }

    const adminClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { autoRefreshToken: false, persistSession: false } },
    );

    const { data: client, error: clientErr } = await adminClient
      .from("clients")
      .select("id")
      .eq("id", clientId)
      .maybeSingle();
    if (clientErr) return jsonResponse({ error: clientErr.message }, 400);
    if (!client) return jsonResponse({ error: "Unknown client link. Please double-check the URL you were given." }, 400);

    const { error: insertErr } = await adminClient.from("client_controlling_doc_responses").insert({
      client_id: clientId,
      respondent_name: clampText(data.respondentName),
      respondent_email: clampText(data.respondentEmail),
      overall_notes: clampText(data.overallNotes),
      question_responses: cleanResponses,
    });
    if (insertErr) return jsonResponse({ error: insertErr.message }, 400);

    // Write the client's ranking / notes back onto each question so the
    // internal Controlling Document form shows what the client said. Skip
    // questions the client left untouched -- otherwise a blank entry would
    // wipe a ranking/note staff had already put on that question. Best
    // effort: a failed write-back doesn't undo the recorded submission.
    for (const r of cleanResponses) {
      if (!r.question_id) continue;
      if (r.ranking === null && r.notes === null) continue;
      await adminClient
        .from("client_research_questions")
        .update({ ranking: r.ranking, customer_notes: r.notes })
        .eq("id", r.question_id)
        .eq("client_id", clientId);
    }

    return jsonResponse({ ok: true });
  } catch (e) {
    return jsonResponse({ error: e instanceof Error ? e.message : "Unexpected error." }, 500);
  }
});
