-- 084_cleanup_extremis_research_questions.sql
--
-- Greg (8/26/26): "do a one time removal of the Extremis Questions. Now
-- that we've deleted the question editor i don't have a place to remove
-- them." The Research page (client_research.html) no longer has any
-- per-question UI -- it went to flat upload-or-link per research area --
-- so old client_research_questions rows for Extremis Systems (with the
-- old question text baked in) are stuck showing on the client-facing
-- Dashboard with no way to clear them from inside the app.
--
-- This is a ONE-TIME DATA CLEANUP, not a schema change -- it deletes rows,
-- it doesn't alter any table. Nothing else needs this table cleaned up
-- (only Extremis Systems came up), so this only touches that one client's
-- rows. The client_research_questions table itself is left in place,
-- exactly as it already was left untouched by the Research page
-- simplification -- just emptied out for this one client.
--
-- Order matters: documents.question_id -> client_research_questions(id)
-- is ON DELETE CASCADE (see 033_research_questions.sql), so deleting a
-- question row would silently delete any document still pointed at it.
-- Step 1 detaches any such documents first (clearing question_id, keeping
-- research_area so the file/link itself is untouched and still shows up
-- normally) so step 2's delete can't take anything down with it. As of
-- 8/26/26 no documents were actually uploaded yet for Extremis (all 4
-- areas showed "No files shared yet"), so step 1 is expected to be a
-- no-op here -- it's just cheap insurance.
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
