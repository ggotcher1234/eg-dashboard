-- set_excaliber_overdue_test.sql (v2)
--
-- One-off test-data tweak, not a schema migration -- Greg wants to see how
-- an overdue engagement actually looks on the Home page for Chris/Admins
-- before it happens for real. The Home page's overdue badge and status dot
-- both key off "days since" checks (index.html):
--   - overdue badge: daysSince(last_activity_at || updated_at) >= 60
--   - status dot:    daysSince(first_in_progress_at || status_since) >= 60 -> red
--
-- v1 of this script set all 4 columns in one UPDATE. Greg ran it twice and
-- confirmed both times that the red dot + "Started: Jun 29" (driven by
-- first_in_progress_at/status_since) took the backdate correctly, but the
-- Overdue badge (driven by last_activity_at/updated_at) never appeared.
-- Since all 4 columns are set in the same statement, the only way 2 of 4
-- could silently fail to stick is a trigger on clients that unconditionally
-- re-stamps last_activity_at (and/or updated_at) to now() on every write to
-- the row -- including this very UPDATE statement. That matches the
-- "last_activity_at is kept current by DB triggers..." note in index.html;
-- its source migration (053_client_activity_tracking.sql) isn't in this
-- repo folder to confirm the trigger's name, but the effect lines up
-- exactly: it's designed to snap back to "now" the instant the row is
-- touched, which defeats a manual backdate every time.
--
-- Fix: disable clients' triggers just for this one update so the backdated
-- value actually sticks, then turn them back on immediately after.
-- Purely test-data, Excaliber only -- safe to re-run.

-- "all" also tries to disable Postgres's own internal foreign-key
-- constraint triggers, which errors with "permission denied ... is a
-- system trigger" even for the table owner (42501) on Supabase. "user"
-- disables only our own custom triggers (which is all we need to bypass
-- here) and leaves the built-in FK ones alone.
alter table clients disable trigger user;

update clients
set last_activity_at = now() - interval '61 days',
    updated_at = now() - interval '61 days',
    first_in_progress_at = now() - interval '61 days',
    status_since = now() - interval '61 days'
where name = 'Excaliber';

alter table clients enable trigger user;
