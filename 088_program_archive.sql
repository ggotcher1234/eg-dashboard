-- 088_program_archive.sql
--
-- Depends on 001_foundation_schema.sql (econ_dev_companies).
--
-- Greg (8/28/26, per the platform review meeting): the only way to retire
-- a Program used to be the hard "Remove" on econ_dev_partners_admin.html,
-- which permanently deletes the row (existing clients keep their history,
-- but the Program itself is gone -- can't be undone, can't be relisted).
-- This adds a real soft-archive alongside it: an Archive/Unarchive toggle
-- that just hides the Program from the default Programs list, with a
-- "Show archived" checkbox to bring it back into view, same pattern as the
-- Engagements list's "Show closed" checkbox added the same day. The old
-- hard delete stays exactly as it was, for true data-entry mistakes only.
--
-- Safe to re-run.

alter table econ_dev_companies add column if not exists archived boolean not null default false;
