-- set_excaliber_overdue_test.sql
--
-- One-off test-data tweak, not a schema migration -- Greg wants to see how
-- an overdue engagement actually looks on the Home page for Chris/Admins
-- before it happens for real. The Home page's overdue badge and status dot
-- both key off "days since" checks (index.html):
--   - overdue badge: daysSince(last_activity_at || updated_at) >= 60
--   - status dot:    daysSince(first_in_progress_at || status_since) >= 60 -> red
-- This backdates Excaliber's activity/start timestamps to 61 days ago so
-- both trip at once. Purely cosmetic test data -- doesn't touch anything
-- else about the engagement (hours, documents, assignments, etc.).
--
-- To undo: re-run client_control_center.html's normal activity (log an hour,
-- edit the engagement, etc.) which will bump last_activity_at back to now,
-- or just leave it -- Excaliber is a test account.
--
-- Safe to re-run.

update clients
set last_activity_at = now() - interval '61 days',
    updated_at = now() - interval '61 days',
    first_in_progress_at = now() - interval '61 days',
    status_since = now() - interval '61 days'
where name = 'Excaliber';
