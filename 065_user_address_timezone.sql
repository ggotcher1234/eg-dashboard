-- 065_user_address_timezone.sql
--
-- Chris's National Team Roster spreadsheet (POSITION, NAME, COMPANY,
-- MAILING ADDRESS, TIME ZONE, EMAIL, PHONE) has two columns the Roster page
-- still has nowhere to put: MAILING ADDRESS and TIME ZONE. Company/Email/
-- Phone/Position already round-trip; this adds the last two so Greg can
-- import that file and have every column land somewhere real.
--
-- Plain free-text fields, same shape as `title`/`company_name` -- address
-- is a mailing address string (not parsed into street/city/state), time
-- zone is a plain label (e.g. "Mountain", "Pacific") matching the
-- spreadsheet's own column, not an IANA tz identifier.
--
-- Safe to re-run.

alter table users add column if not exists address text;
alter table users add column if not exists time_zone text;
