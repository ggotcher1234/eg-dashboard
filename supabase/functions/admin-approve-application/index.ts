// admin-approve-application
//
// Greg (9/25/26, from the call): "when an application is submitted, Chris
// needs to approve it... Only he can check it. When he checks it an email
// needs to go out to the PA and Rita letting them know that the new Applicant
// (Name) has been approved on 'date'. Then Rita will go in and add the hours
// and TL which will kick off the engagement for the EG Team."
//
// WHY A FUNCTION AND NOT A PLAIN UPDATE FROM THE PAGE
// Two reasons, and either one on its own would be enough:
//   * the notification. RESEND_API_KEY lives in Edge Function secrets and
//     must never reach a browser, so anything that sends email has to run
//     here. It also has to read the Program's contacts and the Admin list to
//     know who to tell, which the service-role client does without depending
//     on the caller's RLS view;
//   * the permission. "Only he can check it" is a property of a person
//     (users.can_approve_applications, 129) and it is proved HERE, server
//     side, once. The page hides and disables the checkbox for everyone else,
//     but that is courtesy -- this is the part that actually holds.
//
// Approving is idempotent: a second POST for an already-approved application
// changes nothing and sends nothing, so a double-click or a stale tab cannot
// email the Program twice.
//
// Un-approving (approved: false) clears the stamp and sends NO email. If the
// approver ticks the box by mistake the correction is silent -- a "never mind"
// note to the Program Administrator would be worse than the mistake.
//
// HOW TO DEPLOY (no CLI, no Terminal)
//   1. Supabase Dashboard -> Edge Functions -> New Function, named exactly
//      admin-approve-application
//   2. Paste this whole file in, Deploy
//   3. It uses the same RESEND_API_KEY secret public-submit-application
//      already uses -- nothing new to add.
//   SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are
//   provided to every Edge Function automatically.
//
// DEPLOY ORDER: run 129_application_approval.sql first. Without the columns
// this function 400s on every call, and without the flag nobody can approve.

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

// The date in the email should be the date the approver saw on their own
// screen when they ticked the box. An approval at 7pm Denver time is 2am UTC
// the next day, and "approved on the 26th" for something Chris did on the
// 25th is the kind of small wrongness that makes people distrust the whole
// notice. So the page sends its own IANA zone and we format the stamp in it;
// anything unusable falls back to UTC rather than throwing.
function formatApprovalDate(iso: string, timeZone: unknown): string {
  const opts: Intl.DateTimeFormatOptions = {
    year: "numeric",
    month: "long",
    day: "numeric",
  };
  const tz = typeof timeZone === "string" && timeZone.length > 0 && timeZone.length < 64
    ? timeZone
    : "UTC";
  try {
    return new Date(iso).toLocaleDateString("en-US", { ...opts, timeZone: tz });
  } catch {
    return new Date(iso).toLocaleDateString("en-US", { ...opts, timeZone: "UTC" });
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";

    // Acts AS the caller -- used only to establish who is asking.
    const callerClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data: userData, error: userErr } = await callerClient.auth.getUser();
    if (userErr || !userData?.user) {
      return jsonResponse({ error: "Not signed in." }, 401);
    }

    const { data: caller, error: callerErr } = await callerClient
      .from("users")
      .select("id, full_name, role, can_approve_applications, archived_at")
      .eq("id", userData.user.id)
      .single();

    if (callerErr || !caller) {
      return jsonResponse({ error: "Couldn't read your profile." }, 403);
    }
    // Belt and braces, same as admin-create-team-member: an archived account
    // is banned from signing in, but a token issued just before the ban stays
    // valid for up to an hour.
    if (caller.archived_at) {
      return jsonResponse({ error: "This account has been archived." }, 403);
    }
    if (!caller.can_approve_applications) {
      return jsonResponse({
        error: "Only the person who holds application approval can tick this box.",
      }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const applicationId = body.application_id;
    if (!applicationId) {
      return jsonResponse({ error: "application_id is required." }, 400);
    }
    if (typeof body.approved !== "boolean") {
      // Explicit boolean rather than a truthy flag, so a malformed body can
      // never be read as "approve it".
      return jsonResponse({ error: "approved must be true or false." }, 400);
    }
    const approved: boolean = body.approved;

    const adminClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { autoRefreshToken: false, persistSession: false } },
    );

    const { data: app, error: appErr } = await adminClient
      .from("client_applications")
      .select("id, company_name, primary_officer_name, econ_dev_company_id, status, approved_at, approved_by")
      .eq("id", applicationId)
      .maybeSingle();

    if (appErr) return jsonResponse({ error: `Couldn't read the application: ${appErr.message}` }, 500);
    if (!app) return jsonResponse({ error: "That application no longer exists." }, 404);

    // ---------- un-approve ----------
    if (!approved) {
      const { error: clearErr } = await adminClient
        .from("client_applications")
        .update({ approved_at: null, approved_by: null })
        .eq("id", app.id)
        .select("id");
      if (clearErr) return jsonResponse({ error: `Couldn't clear the approval: ${clearErr.message}` }, 500);
      return jsonResponse({ ok: true, approved: false, approved_at: null, approved_by: null });
    }

    // ---------- already approved ----------
    // Not an error, and not a second email. Hand back what is already there so
    // the page just shows the existing stamp.
    if (app.approved_at) {
      return jsonResponse({
        ok: true,
        approved: true,
        approved_at: app.approved_at,
        approved_by: app.approved_by,
        already: true,
      });
    }

    // ---------- approve ----------
    const approvedAt = new Date().toISOString();
    const { data: updated, error: updErr } = await adminClient
      .from("client_applications")
      .update({ approved_at: approvedAt, approved_by: caller.id })
      .eq("id", app.id)
      // .select() so an RLS-shaped silent success (200, no rows) is caught
      // rather than reported as an approval that never happened.
      .select("id, approved_at, approved_by");
    if (updErr) return jsonResponse({ error: `Couldn't save the approval: ${updErr.message}` }, 500);
    if (!updated || updated.length === 0) {
      return jsonResponse({ error: "The approval didn't save -- nothing was written." }, 500);
    }

    // ---------- tell the people who act on it ----------
    // Greg: "an email needs to go out to the PA and Rita." Two groups, and
    // neither is a name in this file:
    //   * the Program Administrator(s) on the Program this application came
    //     through -- the flag set on the Programs page, same one the Accept
    //     form's CC picker treats as always-copied;
    //   * every active Admin account, which today is Chris, Rita and Greg.
    //     Rita is who Greg named, and she is reached by being an Admin, so
    //     this keeps working when the team changes.
    // The approver is included rather than filtered out: a copy of what went
    // to the Program is how Chris knows exactly what was said in his name.
    //
    // The approval is saved by this point. Nothing below is allowed to
    // report it as a failure.
    let warning: string | null = null;
    try {
      const resendKey = Deno.env.get("RESEND_API_KEY");
      if (!resendKey) throw new Error("RESEND_API_KEY secret is not set.");

      const [{ data: admins, error: adminsErr }, { data: contacts, error: contactsErr }, { data: program, error: programErr }] =
        await Promise.all([
          adminClient.from("users").select("email").eq("role", "super_admin").is("archived_at", null),
          app.econ_dev_company_id
            ? adminClient
                .from("econ_dev_partner_contacts")
                .select("name, email")
                .eq("partner_id", app.econ_dev_company_id)
                .eq("is_program_administrator", true)
                .eq("active", true)
            : Promise.resolve({ data: [], error: null }),
          app.econ_dev_company_id
            ? adminClient
                .from("econ_dev_companies")
                .select("name, code")
                .eq("id", app.econ_dev_company_id)
                .maybeSingle()
            : Promise.resolve({ data: null, error: null }),
        ]);

      if (adminsErr) throw new Error(`Couldn't look up admins: ${adminsErr.message}`);
      if (contactsErr) throw new Error(`Couldn't look up the Program Administrator: ${contactsErr.message}`);
      if (programErr) throw new Error(`Couldn't look up the Program: ${programErr.message}`);

      const recipients = [...new Set(
        [
          ...(admins ?? []).map((u: { email: string | null }) => u.email ?? ""),
          ...(contacts ?? []).map((c: { email: string | null }) => c.email ?? ""),
        ]
          .map((e: string) => e.trim().toLowerCase())
          .filter((e: string) => e.length > 0),
      )];
      if (recipients.length === 0) throw new Error("Nobody to notify -- no Admin or Program Administrator has an email address on file.");

      const programName = program?.name ?? "";
      const programCode = program?.code ?? "";
      const companyName = app.company_name ?? "This application";
      const officerName = (app.primary_officer_name ?? "").trim();
      const approverName = caller.full_name ?? "an Admin";
      const dateLabel = formatApprovalDate(approvedAt, body.time_zone);

      const res = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${resendKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          // Same verified sending domain as every other system email --
          // see the long note in public-submit-application.
          from: "EG Dashboard <noreply@send.economicgardening.org>",
          reply_to: "egdashboard@economicgardening.org",
          to: recipients,
          // The "(CODE) Subject" convention Greg set on 9/14/26, so everything
          // this app sends sorts together in an inbox.
          subject: programCode
            ? `(${programCode}) Application Approved - ${companyName}`
            : `Application Approved - ${companyName}`,
          html: `
            <p><strong>${escapeHtml(companyName)}</strong> was approved for the Economic Gardening Program on ${escapeHtml(dateLabel)}.</p>
            <p>
              <strong>Company:</strong> ${escapeHtml(companyName)}<br/>
              ${officerName ? `<strong>Primary Contact:</strong> ${escapeHtml(officerName)}<br/>` : ""}
              ${programName ? `<strong>Program:</strong> ${escapeHtml(programName)}${programCode ? ` (${escapeHtml(programCode)})` : ""}<br/>` : ""}
              <strong>Approved by:</strong> ${escapeHtml(approverName)}
            </p>
            <p>Next step: assign the budget hours and a Team Lead on the Applications tab. That accepts the application and starts the engagement for the EG team.</p>
          `,
        }),
      });
      if (!res.ok) {
        const errText = await res.text().catch(() => "");
        throw new Error(`Resend returned ${res.status}: ${errText}`);
      }
    } catch (emailErr) {
      const detail = emailErr instanceof Error ? emailErr.message : String(emailErr);
      console.error("Approval notification failed:", detail);
      warning = `Approved, but the notification email didn't send: ${detail}`;
    }

    return jsonResponse({
      ok: true,
      approved: true,
      approved_at: approvedAt,
      approved_by: caller.id,
      approver_name: caller.full_name,
      warning,
    });
  } catch (e) {
    return jsonResponse({ error: e instanceof Error ? e.message : "Unexpected error." }, 500);
  }
});

// .split/.join rather than regex literals -- a bare `/</g` token in an Edge
// Function file has tripped up Supabase's deploy-time parser before.
function escapeHtml(str: string) {
  return String(str)
    .split("&").join("&amp;")
    .split("<").join("&lt;")
    .split(">").join("&gt;")
    .split('"').join("&quot;");
}
