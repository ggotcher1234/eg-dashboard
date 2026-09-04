-- 111_public_application_submitted_by_nullable.sql
--
-- Depends on: client_applications (predates this repo's numbered
-- migrations, same as 066's equivalent fix for client_application_drafts).
--
-- Greg (9/4/26): public-submit-application was rewritten to insert
-- straight into client_applications instead of client_application_drafts
-- (see that function's own comment for why the old "insert as a draft"
-- design existed and why it's gone now). client_applications.submitted_by
-- is set by every OTHER insert path (the internal wizard always has a
-- signed-in staff member creating it), so it may well be `not null` --
-- a public submission has no logged-in user at all, so this has to allow
-- null the same way 066 already did for client_application_drafts.created_by.
--
-- Harmless no-op if the column is already nullable.
--
-- Safe to re-run.

alter table client_applications alter column submitted_by drop not null;
