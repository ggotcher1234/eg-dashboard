-- 125_archive_roster_members.sql   (9/23/26)
--
-- Rita (9/23/26): "Is there a way to archive roster members? I think we need a
-- way to archive them."
-- Greg (9/23/26): "we will never delete just archive. archived members will
-- lose all access to any EG information so we may want to keep the hide
-- checkbox so if we don't want them to show up in the general roster we can
-- hide them. So - delete - no, hide - yes, archive - yes. i do not want anyone
-- to have to do any data entry on archive, only admins can archive or hide.
-- archive auto saves the data and the admin that archived them. we will need a
-- view archived button."
--
-- WHY NOT JUST REUSE hidden_from_roster
-- 108_hidden_from_roster.sql added that flag for one job, and it still has it:
-- Chris, Rita and Greg hold super_admin accounts that should not appear in the
-- Roster or in specialist pick lists. That is a standing property of an account
-- ("staff, not a specialist"), and 108 is explicit that it changes nothing
-- else -- "Their own profile and sign-in are unaffected."
--
-- Archiving is a different thing in three ways, and a second boolean could not
-- express any of them:
--   * it is an EVENT, so it has a date and an author. A checkbox tells you the
--     state and nothing about how it got there, which is exactly why Greg
--     called hiding "a pretty nebulous approach to archiving -- you don't know
--     what's really happening";
--   * it is REVIEWABLE. Hidden people are only visible behind a "Show hidden"
--     checkbox that mixes them into the live list; archived people get a list
--     of their own;
--   * it REVOKES ACCESS. Hiding deliberately does not.
-- So the two live side by side. A person can be hidden, archived, both, or
-- neither, and each answers its own question.
--
-- WHAT THIS MIGRATION DOES AND DOES NOT DO
-- It adds the two columns and nothing else. There is deliberately no trigger,
-- no default, and no RLS change here:
--   * the WRITE is done by the admin-create-team-member Edge Function, which
--     already proves the caller is a super_admin before it touches anything.
--     Keeping one gate means "only admins can archive" is enforced in one
--     place, server-side, not re-implemented in a policy that could drift.
--   * ACCESS REVOCATION is done in that same function by banning the person's
--     Supabase Auth account, which stops them signing in at all. That is a
--     stronger and much smaller change than editing RLS policies one by one,
--     and it does not depend on knowing every policy in the project.
--     Caveat worth knowing: an access token already issued stays valid until
--     it expires (an hour by default). Banning stops the next refresh, so a
--     signed-in archived user is out within the hour rather than instantly.
--
-- NOTHING IS DELETED, EVER. Archiving leaves client_assignments and
-- time_entries exactly as they are -- past invoices and Team & Hours rows keep
-- resolving the person's name. That is the point of archiving instead of
-- deleting, and it is why the Delete action is being retired from the Roster in
-- the same change.
--
-- Safe to re-run.

alter table users
  add column if not exists archived_at timestamptz,
  add column if not exists archived_by uuid references users(id) on delete set null;

comment on column users.archived_at is
  'When this person was archived. Null = active. Archived people are hidden from the Roster''s default view and from every assignment picker, their Supabase Auth account is banned so they cannot sign in, and all of their assignments and logged hours are left untouched. Set by the admin-create-team-member Edge Function, never by hand.';

comment on column users.archived_by is
  'The super_admin who archived this person. ON DELETE SET NULL so removing an admin account never erases the archived record itself.';

-- Archived people are the small minority and are always fetched as their own
-- list, so a partial index is the right shape -- it stays tiny and the planner
-- can use it for the Archived view without weighing on the far more common
-- "active roster" scan.
create index if not exists users_archived_at_idx
  on users (archived_at desc)
  where archived_at is not null;

-- Sanity check: both columns present, nobody archived yet.
select
  count(*)                                        as roster_rows,
  count(*) filter (where archived_at is not null) as archived_rows,
  count(*) filter (where hidden_from_roster)      as hidden_rows
from users;
