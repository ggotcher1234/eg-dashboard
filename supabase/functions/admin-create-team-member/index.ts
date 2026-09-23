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
//   team_directory.html's "+ Add Team Member" button (POST), and its
//   "Set Password", "Archive Member" and "Restore" actions in the profile
//   modal (PATCH, Super Admin only) — via normal fetch() calls using the
//   signed-in Super Admin's own session token — never the service role key,
//   which never leaves this function.
//
// ARCHIVE / RESTORE (PATCH with { user_id, archived: true | false })
//   Greg (9/23/26): "we will never delete just archive... archived members
//   will lose all access to any EG information... i do not want anyone to have
//   to do any data entry on archive, only admins can archive or hide. archive
//   auto saves the data and the admin that archived them."
//
//   So archiving takes no input beyond who to archive. It stamps
//   users.archived_at / archived_by (125_archive_roster_members.sql) and BANS
//   the person's Supabase Auth account, which is what actually takes their
//   access away -- they cannot sign in, and their session cannot refresh.
//   One caveat, stated plainly because it is easy to assume otherwise: an
//   access token already in a browser stays valid until it expires, an hour by
//   default. Somebody signed in at the moment you archive them is out within
//   the hour, not that second.
//
//   Nothing is deleted. Assignments and logged hours stay exactly where they
//   are, so past invoices and Team & Hours rows still resolve the name.
//   Restore is the same call with archived: false -- it clears both columns
//   and lifts the ban.
//
//   Two refusals, both about not locking the org out of itself: an admin
//   cannot archive their own account, and the last active super_admin cannot
//   be archived.
//
// WHY THERE IS NO LONGER A DELETE
//   Greg (9/23/26): "delete - no". Hard delete was the only way to take
//   somebody off the Roster, which meant the irreversible action was also the
//   everyday one. Archive replaces it outright and the DELETE branch is gone --
//   the method is refused with a message rather than quietly 404ing, in case an
//   older cached copy of team_directory.html is still calling it.
//
// SET PASSWORD (PATCH)
//   Supabase's built-in email sender (used by "Forgot your password?" and
//   the Dashboard's "Send password recovery") is rate-limited to just a
//   few emails per hour on the default relay — meant for testing, not real
//   use (Greg, 8/17/26). Rather than fight that limit, a Super Admin can
//   set someone's password directly here, no email involved at all.
//
// WHAT THE OLD DELETE SAFETY CHECK WAS PROTECTING
//   client_assignments.user_id and time_entries.consultant_id both cascade off
//   users(id), so a raw delete of a team member silently wiped their client
//   assignments AND logged hours. The old DELETE branch checked for both and
//   refused. Archiving makes that whole class of accident impossible: it never
//   removes a row, so there is nothing to check for and nothing to lose.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, PATCH, OPTIONS",
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
  // DELETE used to remove a team member outright. Roster members are archived
  // now, never deleted (Greg, 9/23/26), so it is answered rather than dropped --
  // a stale cached page calling it should say something useful.
  if (req.method === "DELETE") {
    return jsonResponse({
      error: "Roster members are archived, not deleted. Reload the Roster page and use Archive Member.",
    }, 405);
  }
  if (req.method !== "POST" && req.method !== "PATCH") {
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
      .select("role, organization_id, archived_at")
      .eq("id", userData.user.id)
      .single();

    if (profileErr || !callerProfile || callerProfile.role !== "super_admin") {
      return jsonResponse({ error: "Only an Admin can add, archive or restore roster members." }, 403);
    }
    // Belt and braces. An archived admin should never get this far -- their
    // auth account is banned, so they cannot hold a session -- but a token
    // issued just before the ban stays valid for up to an hour, and archiving
    // people is not something to leave open during that window.
    if (callerProfile.archived_at) {
      return jsonResponse({ error: "This account has been archived." }, 403);
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

    if (req.method === "PATCH") {
      const targetId = body.user_id;

      // ---- Archive / Restore ----
      // Checked before the password branch because it is the only PATCH that
      // carries no password, and `archived` is an explicit boolean rather than
      // a truthy flag so that a malformed body can't be read as "archive".
      if (typeof body.archived === "boolean") {
        if (!targetId) {
          return jsonResponse({ error: "user_id is required." }, 400);
        }

        const { data: target, error: targetErr } = await adminClient
          .from("users")
          .select("id, full_name, role, archived_at")
          .eq("id", targetId)
          .single();

        if (targetErr || !target) {
          return jsonResponse({ error: "That roster member no longer exists." }, 404);
        }

        if (body.archived) {
          if (targetId === userData.user.id) {
            return jsonResponse({
              error: "You can't archive your own account. Ask another Admin to do it.",
            }, 400);
          }

          // Archiving the last working Admin would leave nobody able to
          // restore anyone -- including the person who just did it.
          if (target.role === "super_admin") {
            const { count: activeAdmins } = await adminClient
              .from("users")
              .select("id", { count: "exact", head: true })
              .eq("role", "super_admin")
              .is("archived_at", null);
            if ((activeAdmins || 0) <= 1) {
              return jsonResponse({
                error: "This is the only active Admin left. Make someone else an Admin first.",
              }, 400);
            }
          }

          const { error: archErr } = await adminClient
            .from("users")
            .update({ archived_at: new Date().toISOString(), archived_by: userData.user.id })
            .eq("id", targetId);
          if (archErr) {
            return jsonResponse({ error: archErr.message }, 400);
          }

          // What actually takes their access away. 876000h is 100 years --
          // Supabase has no "forever", and Restore lifts it anyway.
          const { error: banErr } = await adminClient.auth.admin.updateUserById(targetId, {
            ban_duration: "876000h",
          });
          if (banErr) {
            // The row is already stamped, so say what did and didn't happen
            // rather than reporting a clean success or rolling back a record
            // that is, on its own, correct.
            return jsonResponse({
              error: `Archived on the Roster, but their sign-in could not be blocked: ${banErr.message}`,
            }, 500);
          }

          return jsonResponse({ ok: true, archived: true });
        }

        // ---- Restore ----
        const { error: unArchErr } = await adminClient
          .from("users")
          .update({ archived_at: null, archived_by: null })
          .eq("id", targetId);
        if (unArchErr) {
          return jsonResponse({ error: unArchErr.message }, 400);
        }

        const { error: unbanErr } = await adminClient.auth.admin.updateUserById(targetId, {
          ban_duration: "none",
        });
        if (unbanErr) {
          return jsonResponse({
            error: `Restored on the Roster, but their sign-in could not be re-enabled: ${unbanErr.message}`,
          }, 500);
        }

        return jsonResponse({ ok: true, archived: false });
      }

      // ---- Set password ----
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
    const address = (body.address || "").trim() || null;
    const time_zone = (body.time_zone || "").trim() || null;
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
      company_name,
      email,
      phone,
      secondary_email,
      address,
      time_zone,
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
