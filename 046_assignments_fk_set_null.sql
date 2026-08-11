-- 046_assignments_fk_set_null.sql
--
-- Bug found live: client_assignments.user_id has an ON DELETE CASCADE
-- foreign key back to users(id) (set up pre-017, before this repo tracked
-- migrations -- confirmed live via pg_constraint on 2026-08-11). That means
-- deleting a users row -- which happens whenever a consultant's Supabase
-- Auth login gets deleted/recreated (see 044_relink_user_account.sql) --
-- doesn't just orphan their assignment rows, it DELETES them outright.
--
-- This silently destroyed a client's Team Lead row (a "fixed slot" that the
-- app's own UI deliberately protects from hard deletion -- see
-- client_workspace.html's isFixed / "Clear" vs "Remove" logic) the moment
-- the assigned consultant's old Auth user was deleted, even though nothing
-- in the app itself ever issued a delete.
--
-- Fix: change the FK to ON DELETE SET NULL. This makes an account deletion
-- behave exactly like clicking "Clear" on that row (user_id -> null, row
-- stays) instead of silently deleting it -- consistent with how every other
-- "remove a consultant" action in the app already behaves, and it means
-- fixed slots (team_lead, admin, quality_control, etc.) can never vanish
-- just because someone's login got rebuilt.

alter table client_assignments
  drop constraint if exists client_assignments_user_id_fkey;

alter table client_assignments
  add constraint client_assignments_user_id_fkey
  foreign key (user_id) references users(id) on delete set null;
