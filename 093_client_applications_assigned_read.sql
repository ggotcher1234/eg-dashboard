-- 093_client_applications_assigned_read.sql
--
-- Chris (8/29/26): any EG staff member working an engagement should be able
-- to view its original intake application, read-only -- not just the Team
-- Lead and Admins. client_applications currently only lets Team Lead/Admin
-- through on SELECT (the old Podio-parity restriction), but that policy's
-- exact definition predates this repo's tracked migrations, so it isn't
-- here to edit directly. That's fine -- Postgres OR's together every
-- PERMISSIVE policy on a table, so adding a second, broader one is enough
-- to open it up without needing to know or touch whatever the original
-- looks like.
--
-- Scoped narrowly: only ACCEPTED applications (client_id is set) and only
-- to users actually assigned to that resulting client via
-- is_assigned_to_client() (the same "any assigned specialist" check used
-- everywhere else in the app -- client_contacts, client_content, etc.).
-- Pending applications (no client yet) are untouched -- still Team
-- Lead/Admin only, same as today.
--
-- Safe to re-run.

drop policy if exists client_applications_assigned_select on client_applications;
create policy client_applications_assigned_select on client_applications for select
using (
  is_super_admin()
  or (client_id is not null and is_assigned_to_client(client_id))
);
