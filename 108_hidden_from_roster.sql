-- 108_hidden_from_roster.sql
--
-- Chris / Greg (9/2/26): "Can we make Chris, Rita and I hidden admins. Our
-- name and that role should not be in the Roster even though we have that
-- role... Podio does not give them that info."
--
-- users.hidden_from_roster is a display-only flag. A hidden user keeps
-- every super_admin capability (no RLS or role change) -- they're just
-- filtered out of every staff-facing people list: the Roster table and its
-- role counts / workload card, all specialist / team-lead pick lists
-- (Workspace, Control Center, Invoicing, Team & Hours, Programs), and
-- global search. Their own profile and sign-in are unaffected.
--
-- Toggle it per user from team_directory.html (the "Hide from Roster"
-- checkbox in the member editor) so adding / removing a hidden admin later
-- needs no code change. The one-time UPDATE below is optional -- fill in
-- the three emails and uncomment it, or just use the checkbox.
--
-- Safe to re-run.

alter table users add column if not exists hidden_from_roster boolean not null default false;

-- One-time seed (optional). Uncomment and set the real addresses:
-- update users set hidden_from_roster = true
-- where lower(email) in (
--   'chris@economicgardening.org',
--   'rita@economicgardening.org',
--   'greg@leadforcesolutions.com'
-- );
