-- 063_user_company_name.sql
--
-- Greg (8/20/26): "need a field for Company Name. each roster member has
-- their own company" -- most specialists are independent contractors
-- running their own consulting business, not NCEG employees, so their
-- company name is a real, distinct piece of directory info alongside
-- title/phone/email. Plain free-text field, same shape as `title`.
--
-- Also matches the source roster spreadsheet's existing COMPANY column
-- (see team_directory.html's CSV importer comments) -- that column was
-- previously parsed and then silently dropped since there was nowhere to
-- put it.
--
-- Safe to re-run.

alter table users add column if not exists company_name text;
