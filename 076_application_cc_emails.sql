-- 076_application_cc_emails.sql
--
-- Chris, via Greg (8/24/26): on the Engagement Application's Contacts step,
-- add a category after the 2nd Officer (Secondary Contact) for "Others to
-- include on email cc: list" -- people who should be cc'd on correspondence
-- with this company but aren't a named contact themselves (e.g. a
-- bookkeeper, an assistant).
--
-- Same treatment as the existing social_links/news_links columns already on
-- this table: a plain text[] list, application-only (not auto-copied into
-- the live `clients` record at accept time -- see 043_company_info_from_
-- application.sql's reasoning for why social_links/news_links stay manual
-- rather than guessing how free-text should map onto structured fields).
-- If EG ever wants this to actually drive an outgoing email's CC line, that
-- would be a separate, deliberate wiring decision later.
--
-- Safe to re-run.

alter table client_applications add column if not exists cc_emails text[];
