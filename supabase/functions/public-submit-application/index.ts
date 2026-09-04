// public-submit-application
//
// The one Edge Function a Program's public application page talks to. This
// page has NO login behind it at all -- a CEO gets a link from their
// Program (e.g. Alloy Development), fills it out, hits Submit. There's no
// Supabase session to attach the write to, so this function is the entire
// write path: it validates what came in and inserts the submission
// straight into client_applications (status defaults to 'pending' --
// same row Rita opens on the Applications tab), then emails Chris, Rita,
// and Greg that a new one showed up.
//
// Greg (9/4/26): rewritten. This used to insert into
// client_application_drafts (source = 'public_application') -- a
// workaround from back when a public submission had nowhere else to land
// under client_applications' RLS. That's no longer the model: "everything
// submitted is just an Application" (no more Draft/Pending as a separate
// concept), and RLS was never actually the obstacle for THIS function
// specifically -- it already writes everything through the service-role
// client below, which bypasses RLS regardless of table. See
// 111_public_application_submitted_by_nullable.sql for the one schema
// change this needed (client_applications.submitted_by has to allow null
// for a submission with no logged-in submitter).
//
// Auth model: the public page still sends the project's anon key as the
// Authorization/apikey headers (same as every other page in this app) --
// that's enough to satisfy Supabase's platform-level "is this a validly
// signed request" check, since the anon key IS a signed JWT for this
// project. This function does NOT require Super Admin, or any signed-in
// user at all -- anyone with the link can submit. All actual
// database writes use the service-role client (never the anon key), the
// same pattern as admin-create-team-member.
//
// HOW TO DEPLOY (no CLI, no Terminal)
//   1. Supabase Dashboard -> Edge Functions -> public-submit-application
//      (or New Function, name it exactly that, if it doesn't exist yet)
//   2. Paste this whole file in, Deploy
//   3. Add a secret (Edge Functions -> Manage secrets): RESEND_API_KEY,
//      set to your Resend API key.
//   That's it -- SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are already
//   available to every Edge Function automatically.
//
// FIELD PAYLOAD SHAPE
//   The public form sends `data` keyed by the SAME field ids the internal
//   "+ New Application" wizard uses (f-company-name, f-street, f-p-name,
//   etc. -- see client_applications.html's own client_applications.insert()
//   payload, which this mirrors column-for-column). The public form
//   doesn't collect everything the internal wizard can (no Program
//   Contact, no 3rd officer, no CC list, no tags, no ownership
//   demographics, no contact temperament) -- those columns are just left
//   null, same as when a staff member leaves them blank.

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

// f-pct-instate is intentionally NOT required (Greg, 8/21/26) -- a CEO may
// not have that figure handy, and it shouldn't block submitting otherwise.
// f-is-private (Ownership) and f-program-contact were removed from the
// public form itself (Greg, 9/2/26) -- dropped from here too; requiring
// either would fail every single submission since the form never sends
// them anymore.
const REQUIRED_KEYS = [
  "f-company-name", "f-street", "f-city", "f-state", "f-county", "f-year-founded",
  "f-p-name", "f-p-title", "f-p-email", "f-p-phone", "f-top-issues",
];

function strOrNull(v: unknown): string | null {
  const s = v == null ? "" : String(v).trim();
  return s === "" ? null : s;
}
function numOrNull(v: unknown): number | null {
  if (v == null || String(v).trim() === "") return null;
  const n = Number(String(v).replace(/[^0-9.-]/g, ""));
  return Number.isFinite(n) ? n : null;
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
    const programCode = (body.programCode || "").trim();
    const incomingData = body.data || {};

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

    const companyName = String(incomingData["f-company-name"]).trim();

    const address = {
      street: strOrNull(incomingData["f-street"]),
      city: strOrNull(incomingData["f-city"]),
      state: strOrNull(incomingData["f-state"]),
      postal: strOrNull(incomingData["f-postal"]),
      county: strOrNull(incomingData["f-county"]),
    };

    // f-news-links is a single URL on the public form (unlike the internal
    // wizard's one-per-line textarea) -- wrapped in an array to match the
    // column's text[] shape.
    const newsLink = strOrNull(incomingData["f-news-links"]);

    const payload = {
      organization_id: program.organization_id,
      econ_dev_company_id: program.id,
      program_contact_id: null,
      company_name: companyName,
      address,
      phone: null,
      year_founded: numOrNull(incomingData["f-year-founded"]),
      website: strOrNull(incomingData["f-website"]),
      country: "United States",
      is_private: null,
      primary_officer_name: strOrNull(incomingData["f-p-name"]),
      primary_officer_title: strOrNull(incomingData["f-p-title"]),
      primary_officer_email: strOrNull(incomingData["f-p-email"]),
      primary_officer_phone: strOrNull(incomingData["f-p-phone"]),
      primary_officer_temperament: null,
      secondary_officer_name: strOrNull(incomingData["f-s-name"]),
      secondary_officer_title: strOrNull(incomingData["f-s-title"]),
      secondary_officer_email: strOrNull(incomingData["f-s-email"]),
      secondary_officer_phone: strOrNull(incomingData["f-s-phone"]),
      secondary_officer_temperament: null,
      tertiary_officer_name: null,
      tertiary_officer_title: null,
      tertiary_officer_email: null,
      tertiary_officer_phone: null,
      cc_emails: null,
      naics_code: strOrNull(incomingData["f-naics"]),
      fte_range_10_to_100: incomingData["f-fte-range"],
      fte_2023: numOrNull(incomingData["f-fte-2023"]),
      fte_2024: numOrNull(incomingData["f-fte-2024"]),
      fte_2025: numOrNull(incomingData["f-fte-2025"]),
      revenue_2023: numOrNull(incomingData["f-rev-2023"]),
      revenue_2024: numOrNull(incomingData["f-rev-2024"]),
      revenue_2025: numOrNull(incomingData["f-rev-2025"]),
      sales_1_to_50m: incomingData["f-sales-range"],
      sales_primarily_external: incomingData["f-sales-external"],
      woman_owned: false,
      minority_owned: false,
      veteran_owned: false,
      disabled_owned: false,
      pct_employees_in_state: numOrNull(incomingData["f-pct-instate"]),
      social_facebook_url: strOrNull(incomingData["f-social-facebook"]),
      social_linkedin_url: strOrNull(incomingData["f-social-linkedin"]),
      social_twitter_url: strOrNull(incomingData["f-social-twitter"]),
      social_instagram_url: strOrNull(incomingData["f-social-instagram"]),
      social_youtube_url: strOrNull(incomingData["f-social-youtube"]),
      social_other_url: strOrNull(incomingData["f-social-other"]),
      news_links: newsLink ? [newsLink] : null,
      tags: null,
      top_business_issues: strOrNull(incomingData["f-top-issues"]),
      submitted_by: null,
    };

    const { data: inserted, error: insertErr } = await adminClient
      .from("client_applications")
      .insert(payload)
      .select("id")
      .single();

    if (insertErr) return jsonResponse({ error: insertErr.message }, 400);

    // ---------- Notify Chris, Rita, and Greg ----------
    // Never let an email hiccup lose the application itself -- the row
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
          // greggotcher@gmail.com can't be used as a Resend "from" address --
          // Resend requires the sender domain be verified via DNS, and Gmail
          // won't let Greg do that for gmail.com. onboarding@resend.dev is
          // Resend's own shared, pre-verified sending domain -- no setup
          // needed, and it can send to any recipient. Swap this for a
          // verified economicgardening.org address later if wanted.
          from: "EG Dashboard <onboarding@resend.dev>",
          to: ["cgibbons@economicgardening.org", "rbenson@economicgardening.org", "greggotcher@gmail.com"],
          subject: `New Application: ${companyName} (${program.name})`,
          html: `
            <p>A new Economic Gardening Program application was just submitted through ${escapeHtml(program.name)}'s application link.</p>
            <p>
              <strong>Company:</strong> ${escapeHtml(companyName)}<br/>
              <strong>Program:</strong> ${escapeHtml(program.name)} (${escapeHtml(program.code)})<br/>
              <strong>Primary Contact:</strong> ${escapeHtml(officerName)}
            </p>
            <p>It's waiting on the Applications tab for review -- assign a Team Lead and hours to accept it, or reject it.</p>
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

    return jsonResponse({ ok: true, applicationId: inserted.id, warning: emailWarning });
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
