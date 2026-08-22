// public-submit-application
//
// The one Edge Function a Program's public application page talks to. This
// page has NO login behind it at all -- a CEO gets a link from their
// Program (e.g. Alloy Development), fills it out, hits Submit. There's no
// Supabase session to attach the write to, so this function is the entire
// write path: it validates what came in, uploads any attachments, inserts
// the application as a DRAFT (client_application_drafts, source =
// 'public_application'), and emails Chris, Rita, and Greg that a new one
// showed up (Greg, 8/21/26).
//
// Auth model: the public page still sends the project's anon key as the
// Authorization/apikey headers (same as every other page in this app) --
// that's enough to satisfy Supabase's platform-level "is this a validly
// signed request" check, since the anon key IS a signed JWT for this
// project. This function does NOT require Super Admin, or any signed-in
// user at all -- anyone with the link can submit. From here on, all actual
// database/storage writes use the service-role client (never the anon
// key), the same pattern as admin-create-team-member.
//
// HOW TO DEPLOY (no CLI, no Terminal)
//   1. Supabase Dashboard -> Edge Functions -> New Function -> name it
//      "public-submit-application"
//   2. Paste this whole file in, Deploy
//   3. Add a secret (Edge Functions -> Manage secrets): RESEND_API_KEY,
//      set to your Resend API key.
//   That's it -- SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are already
//   available to every Edge Function automatically.
//
// FIELD PAYLOAD SHAPE
//   The public form sends `data` keyed by the SAME field ids the internal
//   "+ New Application" wizard already uses (f-company-name, f-street,
//   f-p-name, etc. -- see client_applications.html's wizSerialize()). That
//   means a draft submitted here opens up in that same wizard, already
//   filled in, with zero changes needed to the wizard's restore logic.

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

// Only these keys are ever written into the draft's `data` JSONB -- an
// allowlist, not a blind pass-through of whatever the request body
// contains, since this endpoint has no authenticated caller to trust.
const ALLOWED_FIELD_KEYS = [
  "f-company-name", "f-website", "f-year-founded", "f-is-private", "f-program-contact",
  "f-street", "f-city", "f-state", "f-postal", "f-county",
  "f-p-name", "f-p-title", "f-p-email", "f-p-phone",
  "f-s-name", "f-s-title", "f-s-email", "f-s-phone",
  "f-naics", "f-fte-range", "f-fte-2025", "f-fte-2024", "f-fte-2023", "f-fte-2022",
  "f-sales-range", "f-rev-2025", "f-rev-2024", "f-rev-2023", "f-rev-2022",
  "f-sales-external", "f-pct-instate", "f-top-issues", "f-news-links",
  "_secondaryOpen",
];

// f-pct-instate is intentionally NOT required (Greg, 8/21/26) -- a CEO may
// not have that figure handy, and it shouldn't block submitting otherwise.
const REQUIRED_KEYS = [
  "f-company-name", "f-street", "f-city", "f-state", "f-county", "f-year-founded", "f-is-private",
  "f-p-name", "f-p-title", "f-p-email", "f-p-phone", "f-top-issues",
];

// Combined attachment size cap -- keeps one submission from blowing past
// the Edge Function's request-size limit. 8MB is generous for a handful of
// PDFs/photos; the page tells the CEO this up front too.
const MAX_ATTACHMENTS_BYTES = 8 * 1024 * 1024;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  try {
    const body = await req.json().catch(() => ({}));
    const programCode = (body.programCode || "").trim();
    const incomingData = body.data || {};
    const attachments = Array.isArray(body.attachments) ? body.attachments : [];

    if (!programCode) {
      return jsonResponse({ error: "Missing program." }, 400);
    }

    for (const key of REQUIRED_KEYS) {
      const value = incomingData[key];
      if (value === undefined || value === null || String(value).trim() === "") {
        return jsonResponse({ error: `Missing required field: ${key}` }, 400);
      }
    }
    if (typeof incomingData["f-fte-range"] !== "boolean" || typeof incomingData["f-sales-range"] !== "boolean" || typeof incomingData["f-sales-external"] !== "boolean") {
      return jsonResponse({ error: "Please answer all of the Yes/No questions." }, 400);
    }

    let totalBytes = 0;
    for (const a of attachments) {
      if (!a || !a.filename || !a.dataBase64) continue;
      totalBytes += Math.ceil((a.dataBase64.length * 3) / 4);
    }
    if (totalBytes > MAX_ATTACHMENTS_BYTES) {
      return jsonResponse({ error: "Attachments are too large in total (8MB max). Please remove or shrink a file and resubmit." }, 400);
    }

    const adminClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { autoRefreshToken: false, persistSession: false } },
    );

    const { data: program, error: programErr } = await adminClient
      .from("econ_dev_companies")
      .select("id, name, code, organization_id")
      .ilike("code", programCode)
      .maybeSingle();

    if (programErr) return jsonResponse({ error: programErr.message }, 400);
    if (!program) return jsonResponse({ error: "Unknown program link. Please double-check the URL you were given." }, 400);

    // ---------- Upload attachments (service role -- bypasses storage RLS) ----------
    const submissionId = crypto.randomUUID();
    const uploadedAttachments: { name: string; url: string }[] = [];
    for (const a of attachments) {
      if (!a || !a.filename || !a.dataBase64) continue;
      const safeName = String(a.filename).replace(/[^a-zA-Z0-9._-]/g, "_").slice(0, 120);
      const path = `applications/${submissionId}/${Date.now()}-${safeName}`;
      const bytes = Uint8Array.from(atob(a.dataBase64), (c) => c.charCodeAt(0));
      const { error: uploadErr } = await adminClient.storage
        .from("program-application-attachments")
        .upload(path, bytes, { contentType: a.contentType || "application/octet-stream", upsert: false });
      if (uploadErr) {
        console.error("Attachment upload failed:", uploadErr.message);
        continue; // don't let one bad attachment sink the whole application
      }
      const { data: pub } = adminClient.storage.from("program-application-attachments").getPublicUrl(path);
      uploadedAttachments.push({ name: a.filename, url: pub.publicUrl });
    }

    // ---------- Build the draft's data payload ----------
    const data: Record<string, unknown> = {};
    for (const key of ALLOWED_FIELD_KEYS) {
      if (incomingData[key] !== undefined) data[key] = incomingData[key];
    }
    data["f-econ-dev"] = program.id;
    if (uploadedAttachments.length) data._publicAttachments = uploadedAttachments;
    data._publicSubmission = { programCode: program.code, submittedAt: new Date().toISOString() };

    const companyName = String(incomingData["f-company-name"]).trim();

    const { data: inserted, error: insertErr } = await adminClient
      .from("client_application_drafts")
      .insert({
        organization_id: program.organization_id,
        created_by: null,
        engagement_name: companyName,
        econ_dev_company_id: program.id,
        source: "public_application",
        data,
      })
      .select("id")
      .single();

    if (insertErr) return jsonResponse({ error: insertErr.message }, 400);

    // ---------- Notify Chris, Rita, and Greg ----------
    // Never let an email hiccup lose the application itself -- the draft
    // above is already saved by this point regardless of what happens here.
    let emailWarning: string | null = null;
    try {
      const resendKey = Deno.env.get("RESEND_API_KEY");
      if (!resendKey) throw new Error("RESEND_API_KEY secret is not set.");
      const officerName = String(incomingData["f-p-name"] || "").trim();
      const res = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${resendKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: "greggotcher@gmail.com",
          to: ["cgibbons@economicgardening.org", "rbenson@economicgardening.org", "greggotcher@gmail.com"],
          subject: `New Application: ${companyName} (${program.name})`,
          html: `
            <p>A new Economic Gardening Program application was just submitted through ${escapeHtml(program.name)}'s application link.</p>
            <p>
              <strong>Company:</strong> ${escapeHtml(companyName)}<br/>
              <strong>Program:</strong> ${escapeHtml(program.name)} (${escapeHtml(program.code)})<br/>
              <strong>Primary Contact:</strong> ${escapeHtml(officerName)}
            </p>
            <p>It's waiting as a Draft on the Engagement Applications page (Drafts tab) for review.</p>
          `,
        }),
      });
      if (!res.ok) {
        const errText = await res.text().catch(() => "");
        throw new Error(`Resend returned ${res.status}: ${errText}`);
      }
    } catch (emailErr) {
      console.error("Notification email failed:", emailErr instanceof Error ? emailErr.message : emailErr);
      emailWarning = "Application saved, but the notification email failed to send.";
    }

    return jsonResponse({ ok: true, draftId: inserted.id, warning: emailWarning });
  } catch (e) {
    return jsonResponse({ error: e instanceof Error ? e.message : "Unexpected error." }, 500);
  }
});

// Written with .split/.join instead of regex literals -- a bare `/</g` or
// `/>/g` regex token in this file was tripping up Supabase's deploy-time
// parser ("Expected '}', got '<eof>'"), most likely misread as an
// unclosed JSX-like tag. Same result, no regex involved.
function escapeHtml(str: string) {
  return String(str)
    .split("&").join("&amp;")
    .split("<").join("&lt;")
    .split(">").join("&gt;")
    .split('"').join("&quot;");
}
