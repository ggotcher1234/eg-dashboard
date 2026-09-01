-- 102_cleanup_extremis_research_questions.sql
--
-- Greg (9/1/26): "when i open the Extremis create controlling document it
-- is pulling this information in and it should be blank." Extremis Systems
-- is a test engagement whose client_research_questions rows keep getting
-- re-entered with old-format text (the whole question + "Background:" +
-- notes crammed into the single `question` column, from before the
-- Controlling Document form split into Question / Background / Ranking /
-- Customer Notes). The form is meant to load existing questions so a
-- submitted doc stays editable, so those stale rows show up on open.
--
-- Same one-time data cleanup as 084_cleanup_extremis_research_questions.sql
-- -- deletes rows for this one client only, no schema change. Order
-- matters: documents.question_id -> client_research_questions(id) is
-- ON DELETE CASCADE (033), so step 1 detaches any attached documents
-- (clearing question_id, keeping research_area) before step 2 deletes the
-- question rows.
--
-- Safe to re-run (both statements are no-ops once the rows are gone).

update documents
set question_id = null
where question_id in (
  select id from client_research_questions
  where client_id in (select id from clients where name = 'Extremis Systems')
);

delete from client_research_questions
where client_id in (select id from clients where name = 'Extremis Systems');
