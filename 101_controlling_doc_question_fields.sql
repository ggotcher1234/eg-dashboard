-- 101_controlling_doc_question_fields.sql
--
-- Depends on 033_research_questions.sql.
--
-- The Controlling Document form (controlling_document.html) used to store
-- everything for a question in the single `question` text field -- first
-- line = the red question, following lines = black notes -- and rendered a
-- separate client-facing "review view" from that. Greg (9/1/26): that dual
-- internal/client layout is too hard to keep in sync, so the review view is
-- dropped and each question is now four explicit fields on the internal
-- form:
--
--   question        -- the question itself (unchanged column; still what
--                      shows on the EG Research Reports page)
--   background      -- context / elaboration (internal only)
--   ranking         -- customer ranking, 'A' / 'B' / 'C' (internal only)
--   customer_notes  -- free-text customer notes (internal only)
--
-- The three new columns are internal to the Controlling Document form --
-- get_client_public_view() / finalize_client() still read `question` only,
-- so no function changes here.
--
-- Safe to re-run.

alter table client_research_questions add column if not exists background text;
alter table client_research_questions add column if not exists ranking text;
alter table client_research_questions add column if not exists customer_notes text;
