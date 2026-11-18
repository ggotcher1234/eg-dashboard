// admin-approve-application
//
// Greg (9/25/26, from the call): "when an application is submitted, Chris
// needs to approve it... Only he can check it. When he checks it an email
// needs to go out to the PA and Rita letting them know that the new Applicant
// (Name) has been approved on 'date'. Then Rita will go in and add the hours
// and TL which will kick off the engagement for the NCEG Team."
//
// THIS FUNCTION NO LONGER SENDS EMAIL (17/11/26). It used to notify the
// other Admins the moment an application was vetted; Rita asked for that to
// stop -- see the note further down, at the point where it was sent. What
// goes out now is the vetting letter she sends by hand from the Applications
// tab. All this does is record the vetting.
//
// WHY A FUNCTION AND NOT A PLAIN UPDATE FROM THE PAGE
// The permission. "Only he can check it" is a property of a person
// (users.can_approve_applications, 129) and it is proved HERE, server side,
// once. The page hides and disables the checkbox for everyone else, but that
// is courtesy -- this is the part that actually holds. (The other reason was
// the notification, which needed the Resend secret and the service-role
// client; that reason left with the email.)
//
// Approving is idempotent: a second POST for an already-approved application
// changes nothing, so a double-click or a stale tab does no harm.
//
// Un-approving (approved: false) clears the stamp.
//
// HOW TO DEPLOY (no CLI, no Terminal)
//   1. Supabase Dashboard -> Edge Functions -> New Function, named exactly
//      admin-approve-application
//   2. Paste this whole file in, Deploy
//   3. No secrets needed any more. It used RESEND_API_KEY until the vetting
//      notice was removed on 17/11/26; the secret is still there for the
//      functions that do send mail.
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
    // Not an error. Hand back what is already there so the page just shows
    // the existing stamp.
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

    // ---------- The automatic "Vetted" notice, removed 17/11/26 ----------
    // Rita, to Chris: "When I have selected that the application has been
    // vetted, a generic email goes automatically to the PA, you and me that
    // indicates the program has been vetted. Then I can also send the
    // standard email showing that all categories have been met and the
    // application has been vetted. We don't need that generic email to go
    // out automatically. We just need to send the standard email."
    //
    // So ticking Vetted now only records the vetting. The notice Rita sends
    // by hand from the Applications tab is the one that goes out, and it is
    // the better letter: it says which categories were met, where this one
    // only said that vetting happened.
    //
    // One thing goes with it. The old note told the OTHER Admins that an
    // application had been vetted by somebody else -- see Chris's point on
    // 11/12 that he could not see the PA on the sent line, which is because
    // this only ever went to Admins, never to the PA. Rita sending the real
    // letter covers the Program; what it does not cover is an Admin who is
    // not on her Cc. If that turns out to matter, a bell notification is the
    // right shape for it, not mail.
    //
    // Kept rather than deleted outright: the response still carries a
    // warning field, because client_applications.html reads it, and
    // returning a key that is always null is cheaper than coordinating a
    // change on both sides of the wire.
    const warning: string | null = null;

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
