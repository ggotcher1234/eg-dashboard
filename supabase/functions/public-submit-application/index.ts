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
// f-postal added 9/16/26 (Greg): the postal code was collected but optional.
// GIS is one of the six work areas and zip is the unit most location
// analysis starts from, so it is cheaper to ask the CEO once than to chase
// it afterwards. Safe to require here because the form has always SENT this
// key -- unlike the fields dropped above, which is the distinction that
// matters for this list.
//
// DEPLOY ORDER: push the HTML first, then deploy this function. The other
// way round, a submission from the old page with the box left blank is
// rejected by the server with a raw "Missing required field" instead of the
// friendly in-page prompt.
const REQUIRED_KEYS = [
  "f-company-name", "f-street", "f-city", "f-state", "f-postal", "f-county",
  "f-year-founded", "f-p-name", "f-p-title", "f-p-email", "f-p-phone",
  "f-top-issues",
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
      // Greg (9/6/26): the public form now asks for everything the internal
      // application view has a row for, so these stop being hardcoded.
      // Country keeps "United States" as the fallback -- it's prefilled on
      // the form, and that was the old constant.
      phone: strOrNull(incomingData["f-phone"]),
      year_founded: numOrNull(incomingData["f-year-founded"]),
      website: strOrNull(incomingData["f-website"]),
      country: strOrNull(incomingData["f-country"]) ?? "United States",
      // "Private or Public?" was taken off the public form in the 9/11/26
      // Chris/Rita review, so nothing sends this any more and it lands null.
      // The mapping stays rather than being deleted: the column and the
      // internal view's row are still there for applications collected
      // before the change, and if the question ever comes back this function
      // doesn't need redeploying to accept it again.
      is_private: incomingData["f-is-private"] === "private" ? true
                : incomingData["f-is-private"] === "public" ? false
                : null,
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
      tertiary_officer_name: strOrNull(incomingData["f-t-name"]),
      tertiary_officer_title: strOrNull(incomingData["f-t-title"]),
      tertiary_officer_email: strOrNull(incomingData["f-t-email"]),
      tertiary_officer_phone: strOrNull(incomingData["f-t-phone"]),
      // cc_emails is text[]; the form collects one comma-separated line
      // (076_application_cc_emails.sql). Split, trim, drop blanks -- and
      // stay null rather than [] when nothing was entered, so the internal
      // view's "Add Email CC List..." placeholder still shows.
      cc_emails: (() => {
        const raw = strOrNull(incomingData["f-cc-emails"]);
        if (!raw) return null;
        const list = raw.split(",").map((s) => s.trim()).filter(Boolean);
        return list.length ? list : null;
      })(),
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

    // ---------- Notify every Admin ----------
    // Greg (9/14/26): "Every admin needs to get an email notification and a
    // bell notification when a new application is submitted." The bell half
    // is a database trigger (119_application_notifications_on_real_table.sql);
    // this is the email half.
    //
    // The recipient list used to be three hardcoded addresses. It is now
    // whoever holds the Admin role, so adding or removing an admin in the
    // app is all it takes -- no redeploy of this function.
    //
    // Never let an email hiccup lose the application itself -- the row above
    // is already saved by this point regardless of what happens here.
    let emailWarning: string | null = null;
    try {
      const resendKey = Deno.env.get("RESEND_API_KEY");
      if (!resendKey) throw new Error("RESEND_API_KEY secret is not set.");

      const { data: admins, error: adminsErr } = await adminClient
        .from("users")
        .select("email")
        .eq("role", "super_admin")
        // Greg (9/25/26): "eliminate email to archived admins." Archiving
        // (125_archive_roster_members.sql) bans the person's sign-in, but this
        // function predates it and filtered on role alone -- so somebody who
        // had left kept receiving application notifications they could no
        // longer act on. hidden_from_roster is deliberately NOT filtered:
        // hiding keeps an admin off the Roster and out of pick lists, it was
        // never meant to stop them being told about a new application.
        .is("archived_at", null);
      if (adminsErr) throw new Error(`Couldn't look up admins: ${adminsErr.message}`);

      const recipients = [...new Set(
        (admins ?? [])
          .map((u: { email: string | null }) => (u.email ?? "").trim())
          .filter((e: string) => e.length > 0)
          .map((e: string) => e.toLowerCase()),
      )];
      if (recipients.length === 0) throw new Error("No Admin accounts with an email address on file.");

      const officerName = String(incomingData["f-p-name"] || "").trim();
      const res = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${resendKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          // WHY THIS ADDRESS. Until 9/25/26 this said
          // onboarding@resend.dev -- Resend's shared TESTING domain, which
          // only delivers to the email address on the Resend account itself.
          // Any other recipient got the whole send rejected with a 403, so
          // adding Chris and Rita meant nobody received it, not even Greg.
          // https://resend.com/docs/knowledge-base/403-error-resend-dev-domain
          //
          // send.economicgardening.org was verified in Resend on 9/22/26
          // (DKIM TXT + the two sending CNAMEs, all green), so this now sends
          // as a real EG address and can reach anyone. If this ever reverts to
          // failing for everyone but Greg, check that domain's status first --
          // that is the same symptom.
          //
          // A subdomain rather than the root: the root domain's own mail is
          // untouched by any of this, so EG's day-to-day email cannot be
          // affected by what the dashboard sends.
          from: "EG Dashboard <noreply@send.economicgardening.org>",
          // noreply@ has no mailbox behind it, so a reply would vanish.
          // egdashboard@economicgardening.org is the forwarder Eric set up to
          // Chris -- REPLIES BOUNCE IF THAT ADDRESS DOES NOT EXIST, so if the
          // forwarder was never created, delete this one line rather than
          // leaving it pointing at nothing.
          reply_to: "egdashboard@economicgardening.org",
          to: recipients,
          // Greg (9/14/26): "apply naming convention (GRE) New Application
          // Recieved to internal emails as well" -- the same
          // "(program) subject" shape the customer emails use
          // (customerSubject() in client_workflow_files.html), so everything
          // this app sends sorts and filters the same way in an inbox.
          // No " - action" half: an admin notification is not asking the
          // reader to do one specific thing, and Greg's example had none.
          // The company name moves into the body, which already carries it.
          subject: `(${program.code}) New Application Received`,
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

      // ---------- Confirmation to whoever submitted it ----------
      // Greg (9/25/26): "send the submission sender a confirmation email."
      // Until now an applicant filled in a long form, got a thank-you screen,
      // and then heard nothing -- with no record in their own inbox that it
      // had been received at all. A CEO notices that.
      //
      // Sent as its own request AFTER the admin notification, and its failure
      // is swallowed rather than thrown: a confirmation that does not arrive
      // is a disappointment, but it must never be reported as the application
      // failing, and must never mask the admin notification having succeeded.
      // It is also the one email here that goes to someone outside EG, so it
      // says nothing about internal process.
      const officerEmail = String(incomingData["f-p-email"] || "").trim();
      if (officerEmail) {
        try {
          const confirmRes = await fetch("https://api.resend.com/emails", {
            method: "POST",
            headers: {
              Authorization: `Bearer ${resendKey}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              from: "EG Dashboard <noreply@send.economicgardening.org>",
              reply_to: "egdashboard@economicgardening.org",
              to: [officerEmail],
              subject: `(${program.code}) Application Received - ${companyName}`,
              html: `
                <p>${officerName ? `Hi ${escapeHtml(officerName.split(" ")[0])},` : "Hello,"}</p>
                <p>Thank you for applying to the Economic Gardening Program through ${escapeHtml(program.name)}. We have your application for <strong>${escapeHtml(companyName)}</strong>.</p>
                <p>Our team reviews each application and will be in touch about next steps. If you have a question in the meantime, just reply to this email.</p>
                <p>&mdash; The Economic Gardening Team</p>
              `,
            }),
          });
          if (!confirmRes.ok) {
            const t = await confirmRes.text().catch(() => "");
            console.error(`Applicant confirmation failed: ${confirmRes.status} ${t}`);
          }
        } catch (confirmErr) {
          console.error("Applicant confirmation failed:", confirmErr instanceof Error ? confirmErr.message : String(confirmErr));
        }
      }
    } catch (emailErr) {
      const detail = emailErr instanceof Error ? emailErr.message : String(emailErr);
      console.error("Notification email failed:", detail);
      // Surfaced to the submitting page (which logs it) and to the function
      // logs. Admins are told about the application by the bell regardless,
      // so a failure here delays nothing -- it just means the email copy
      // didn't go out.
      emailWarning = `Application saved, but the notification email failed to send: ${detail}`;
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
