// admin-notify-engagement-started
//
// The letter the Program Administrator gets when an application becomes an
// engagement.
//
// WHY IT LIVES HERE AND NOT IN admin-approve-application
// Chris (9/26/26, relayed by Greg 9/27/26) settled the order of operations,
// and it moved this email:
//
//   1. Chris approves for NCEG. Rita cannot touch the form until he has.
//      -> admin-approve-application. EG Admins only; nothing leaves EG.
//   2. Rita works her checks, sets the budget hours, Team Lead and CC list,
//      and accepts.
//      -> THIS function. The Program Administrator is told, with the Admins
//         copied.
//   3. The PA sends their own acceptance letter to the company, copying EG.
//   4. The Team Lead sends the scheduling note, copying Chris, Rita and the
//      PA -- the Welcome Email composer in client_control_center.html, which
//      already builds exactly that CC line.
//
// Until 9/27/26 the PA was told at step 1. That was wrong twice over: it
// announced an engagement before anyone had been assigned to run it, and it
// closed with "the EG team will assign the hours and a Team Lead from here",
// an instruction that would now arrive after that had already happened.
//
// WHY A FUNCTION AT ALL
// RESEND_API_KEY lives in Edge Function secrets and must never reach a
// browser, and the recipient list is read with the service role so it does
// not depend on the caller's RLS view.
//
// NOT FATAL, EVER. The page calls this after accept_client_application() has
// already created the engagement. If this fails, the engagement still exists
// and is usable; the page says the letter did not go out so somebody can send
// it by hand. Nothing here is allowed to look like the accept failing.
//
// HOW TO DEPLOY (no CLI, no Terminal)
//   1. Supabase Dashboard -> Edge Functions -> Deploy a new function ->
//      Via Editor, named exactly admin-notify-engagement-started
//   2. Paste this whole file in, Deploy
//   3. Settings -> turn OFF "Verify JWT with legacy secret", to match
//      admin-approve-application and admin-create-team-member. The auth
//      check is in the code below.
//   It uses the RESEND_API_KEY secret that already exists.

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

// The date the approver saw on their own screen, not UTC's idea of it -- an
// approval at 7pm Denver is already tomorrow in UTC, and "approved on the
// 27th" for something done on the 26th is the kind of small wrongness that
// makes people distrust the whole notice.
function formatDate(iso: string, timeZone: unknown): string {
  const opts: Intl.DateTimeFormatOptions = { year: "numeric", month: "long", day: "numeric" };
  const tz = typeof timeZone === "string" && timeZone.length > 0 && timeZone.length < 64 ? timeZone : "UTC";
  try {
    return new Date(iso).toLocaleDateString("en-US", { ...opts, timeZone: tz });
  } catch {
    return new Date(iso).toLocaleDateString("en-US", { ...opts, timeZone: "UTC" });
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);

  try {
    const authHeader = req.headers.get("Authorization") ?? "";

    // Acts AS the caller -- only to establish who is asking.
    const callerClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data: userData, error: userErr } = await callerClient.auth.getUser();
    if (userErr || !userData?.user) return jsonResponse({ error: "Not signed in." }, 401);

    const { data: caller, error: callerErr } = await callerClient
      .from("users")
      .select("id, full_name, role, archived_at")
      .eq("id", userData.user.id)
      .single();

    if (callerErr || !caller) return jsonResponse({ error: "Couldn't read your profile." }, 403);
    if (caller.archived_at) return jsonResponse({ error: "This account has been archived." }, 403);
    // Accepting is already an Admin action, so this is the same bar -- no
    // separate permission to keep in step with it.
    if (caller.role !== "super_admin") {
      return jsonResponse({ error: "Only an Admin can send the engagement notice." }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const applicationId = body.application_id;
    if (!applicationId) return jsonResponse({ error: "application_id is required." }, 400);

    const adminClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { autoRefreshToken: false, persistSession: false } },
    );

    const { data: app, error: appErr } = await adminClient
      .from("client_applications")
      .select("id, company_name, primary_officer_name, econ_dev_company_id, client_id, approved_at")
      .eq("id", applicationId)
      .maybeSingle();

    if (appErr) return jsonResponse({ error: `Couldn't read the application: ${appErr.message}` }, 500);
    if (!app) return jsonResponse({ error: "That application no longer exists." }, 404);
    // The whole point of this letter is that the engagement exists. Saying so
    // before it does is the mistake this function was created to fix, so it
    // refuses rather than sending something that is not yet true.
    if (!app.client_id) {
      return jsonResponse({ error: "That application has no engagement yet -- nothing to announce." }, 400);
    }

    const resendKey = Deno.env.get("RESEND_API_KEY");
    if (!resendKey) return jsonResponse({ error: "RESEND_API_KEY secret is not set." }, 500);

    const [{ data: admins, error: adminsErr }, { data: contacts, error: contactsErr }, { data: program, error: programErr }] =
      await Promise.all([
        adminClient.from("users").select("email").eq("role", "super_admin").is("archived_at", null),
        app.econ_dev_company_id
          ? adminClient
              .from("econ_dev_partner_contacts")
              .select("email")
              .eq("partner_id", app.econ_dev_company_id)
              .eq("is_program_administrator", true)
              .eq("active", true)
          : Promise.resolve({ data: [], error: null }),
        app.econ_dev_company_id
          ? adminClient.from("econ_dev_companies").select("name, code").eq("id", app.econ_dev_company_id).maybeSingle()
          : Promise.resolve({ data: null, error: null }),
      ]);

    if (adminsErr) return jsonResponse({ error: `Couldn't look up admins: ${adminsErr.message}` }, 500);
    if (contactsErr) return jsonResponse({ error: `Couldn't look up the Program Administrator: ${contactsErr.message}` }, 500);
    if (programErr) return jsonResponse({ error: `Couldn't look up the Program: ${programErr.message}` }, 500);

    const recipients = [...new Set(
      [
        ...(admins ?? []).map((u: { email: string | null }) => u.email ?? ""),
        ...(contacts ?? []).map((c: { email: string | null }) => c.email ?? ""),
      ].map((e: string) => e.trim().toLowerCase()).filter((e: string) => e.length > 0),
    )];
    if (recipients.length === 0) {
      return jsonResponse({ error: "Nobody to notify -- no Admin or Program Administrator has an email address on file." }, 500);
    }

    const programName = program?.name ?? "";
    const programCode = program?.code ?? "";
    const companyName = app.company_name ?? "This application";
    const officerName = (app.primary_officer_name ?? "").trim();
    // The date on the letter is the date of the APPROVAL, not of the accept.
    // "Approved on" should mean what it says, and the two can be days apart.
    // An application accepted without an approval stamp (only possible from a
    // tab open since before the gate existed) falls back to today rather than
    // printing "Invalid Date".
    const dateLabel = formatDate(app.approved_at ?? new Date().toISOString(), body.time_zone);

    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${resendKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        // Same verified sending domain as every other system email -- see the
        // long note in public-submit-application.
        from: "EG Dashboard <noreply@send.economicgardening.org>",
        reply_to: "egdashboard@economicgardening.org",
        to: recipients,
        subject: programCode
          ? `(${programCode}) Application Approved - ${companyName}`
          : `Application Approved - ${companyName}`,
        html: `
          <p><strong>${escapeHtml(companyName)}</strong> was approved for the Economic Gardening Program on ${escapeHtml(dateLabel)}.</p>
          <p>
            <strong>Company:</strong> ${escapeHtml(companyName)}<br/>
            ${officerName ? `<strong>Primary Contact:</strong> ${escapeHtml(officerName)}<br/>` : ""}
            ${programName ? `<strong>Program:</strong> ${escapeHtml(programName)}${programCode ? ` (${escapeHtml(programCode)})` : ""}<br/>` : ""}
            <strong>Approved by:</strong> NCEG
          </p>
          <p>The engagement is underway and the EG Team Lead will be in touch with the company to schedule the discovery call.</p>
        `,
      }),
    });
    if (!res.ok) {
      const errText = await res.text().catch(() => "");
      return jsonResponse({ error: `Resend returned ${res.status}: ${errText}` }, 500);
    }

    return jsonResponse({ ok: true, notified: recipients.length });
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
