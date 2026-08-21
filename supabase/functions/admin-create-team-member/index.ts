// admin-create-team-member
//
// Supabase Edge Function — the one piece that has to run somewhere other
// than the browser. Creating a login account requires the project's
// service_role secret key, and that key must never be embedded in a web
// page (anyone could view-source and steal full database access). This
// function holds that secret safely on Supabase's side instead, and only
// does one thing: given a Super Admin's request, create a new team
// member's login account AND their directory profile row, in one step,
// with no email sent (matches "stealth dev mode" — nobody gets notified).
//
// Role can be 'consultant', 'team_lead', or 'super_admin' -- creating a
// new Super Admin this way is intentionally allowed (Greg, 8/17/26): the
// caller must already BE a Super Admin to reach this function at all (see
// the check below), so a Super Admin minting another Super Admin is a
// trusted, in-bounds action, not a privilege-escalation hole. Before this
// change, role was hard-restricted to consultant/team_lead only, which
// meant there was no way to create a working Super Admin login through
// the app -- someone would end up with a directory-only row (no real
// Supabase Auth account behind it, so it could never sign in) if they
// tried to work around that some other way, e.g. inserting a row directly
// in the Supabase Table Editor.
//
// HOW TO DEPLOY (no CLI, no Terminal)
//   1. Supabase Dashboard -> Edge Functions -> admin-create-team-member
//   2. Click to edit / deploy a new version
//   3. Paste this whole file in, replacing the existing content
//   4. Click Deploy
//   That's it — SUPABASE_URL, SUPABASE_ANON_KEY, and SUPABASE_SERVICE_ROLE_KEY
//   are already available to every Edge Function automatically; you don't
//   need to configure any secrets by hand.
//
// WHAT CALLS THIS
//   team_directory.html's "+ Add Team Member" button (POST), its Delete
//   button (DELETE, Super Admin only), and its "Set Password" action in the
//   profile modal (PATCH, Super Admin only) — via normal fetch() calls
//   using the signed-in Super Admin's own session token — never the
//   service role key, which never leaves this function.
//
// SET PASSWORD (PATCH)
//   Supabase's built-in email sender (used by "Forgot your password?" and
//   the Dashboard's "Send password recovery") is rate-limited to just a
//   few emails per hour on the default relay — meant for testing, not real
//   use (Greg, 8/17/26). Rather than fight that limit, a Super Admin can
//   set someone's password directly here, no email involved at all.
//
// DELETE SAFETY NOTE
//   client_assignments.user_id and time_entries.consultant_id both cascade
//   off users(id) — a raw delete of a team member would silently wipe any
//   client assignments AND logged hours they have on record. This function
//   checks for both first and refuses to delete (with a clear reason)
//   rather than let that happen quietly.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, DELETE, PATCH, OPTIONS",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const VALID_ROLES = ["consultant", "team_lead", "super_admin"];

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST" && req.method !== "DELETE" && req.method !== "PATCH") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";

    // This client acts AS the caller (their own JWT, not the service role) —
    // used only to confirm who's asking and that they're a Super Admin.
    const callerClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data: userData, error: userErr } = await callerClient.auth.getUser();
    if (userErr || !userData?.user) {
      return jsonResponse({ error: "Not signed in." }, 401);
    }

    const { data: callerProfile, error: profileErr } = await callerClient
      .from("users")
      .select("role, organization_id")
      .eq("id", userData.user.id)
      .single();

    if (profileErr || !callerProfile || callerProfile.role !== "super_admin") {
      return jsonResponse({ error: "Only a Super Admin can add or remove team members." }, 403);
    }

    // From here on we use the service role client — this is the one place
    // in the whole app that key is allowed to be used, and it never leaves
    // this server-side function.
    const adminClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { autoRefreshToken: false, persistSession: false } },
    );

    const body = await req.json().catch(() => ({}));

    if (req.method === "DELETE") {
      const targetId = body.user_id;
      if (!targetId) {
        return jsonResponse({ error: "user_id is required." }, 400);
      }

      const { count: assignmentCount } = await adminClient
        .from("client_assignments")
        .select("id", { count: "exact", head: true })
        .eq("user_id", targetId);

      const { count: timeEntryCount } = await adminClient
        .from("time_entries")
        .select("id", { count: "exact", head: true })
        .eq("consultant_id", targetId);

      if ((assignmentCount || 0) > 0 || (timeEntryCount || 0) > 0) {
        return jsonResponse({
          error: "Can't delete — this person has client assignments or logged hours on record. Removing them would erase that history.",
        }, 400);
      }

      const { error: delProfileErr } = await adminClient.from("users").delete().eq("id", targetId);
      if (delProfileErr) {
        return jsonResponse({ error: delProfileErr.message }, 400);
      }

      await adminClient.auth.admin.deleteUser(targetId);
      return jsonResponse({ ok: true });
    }

    if (req.method === "PATCH") {
      const targetId = body.user_id;
      const password = body.password || "";
      if (!targetId || !password) {
        return jsonResponse({ error: "user_id and password are required." }, 400);
      }
      if (password.length < 6) {
        return jsonResponse({ error: "Password must be at least 6 characters." }, 400);
      }

      const { error: pwErr } = await adminClient.auth.admin.updateUserById(targetId, { password });
      if (pwErr) {
        return jsonResponse({ error: pwErr.message }, 400);
      }
      return jsonResponse({ ok: true });
    }

    const email = (body.email || "").trim().toLowerCase();
    const full_name = (body.full_name || "").trim();
    const title = (body.title || "").trim() || null;
    const company_name = (body.company_name || "").trim() || null;
    const phone = (body.phone || "").trim() || null;
    const secondary_email = (body.secondary_email || "").trim() || null;
    const role = body.role;
    const default_specialty = body.default_specialty || null;

    if (!email || !full_name || !role) {
      return jsonResponse({ error: "Email, full name, and role are required." }, 400);
    }
    if (!VALID_ROLES.includes(role)) {
      return jsonResponse({ error: "Role must be 'consultant', 'team_lead', or 'super_admin'." }, 400);
    }

    const { data: created, error: createErr } = await adminClient.auth.admin.createUser({
      email,
      email_confirm: true, // no email sent
    });

    if (createErr || !created?.user) {
      return jsonResponse({ error: createErr?.message || "Couldn't create the account." }, 400);
    }

    const { error: insertErr } = await adminClient.from("users").insert({
      id: created.user.id,
      organization_id: callerProfile.organization_id,
      role,
      full_name,
      title,
      email,
      phone,
      secondary_email,
      default_specialty,
    });

    if (insertErr) {
      // Don't leave an orphaned login with no profile behind — clean it up
      // so a retry with the same email doesn't collide with "already exists".
      await adminClient.auth.admin.deleteUser(created.user.id);
      return jsonResponse({ error: insertErr.message }, 400);
    }

    return jsonResponse({ id: created.user.id });
  } catch (e) {
    return jsonResponse({ error: e instanceof Error ? e.message : "Unexpected error." }, 500);
  }
});
