-- 164: an Admin can actually remove a Controlling Document response
--      [APPLIED 10/11/26]
--
-- Greg (10/11/26): "i have clicked the Delete Response button on multiple
-- occaisions but it keeps coming back when i reopen this section."
--
-- The button worked and the row stayed. client_controlling_doc_responses
-- carried exactly one policy, for SELECT, so with row-level security on, a
-- removal matched NO rows -- and PostgREST reports that as success, because
-- nothing failed; there was simply nothing the caller was allowed to touch.
-- The page then announced a deletion that had not happened and re-rendered
-- the row it had just failed to remove.
--
-- client_evaluation_responses (081) already carries the admin-only rule this
-- mirrors, and the button is already admin-only in the page. The page side
-- now also checks that a row actually went, so a silent no-op cannot be
-- reported as success again.
create policy "controlling doc responses delete"
  on client_controlling_doc_responses
  for delete
  using (is_super_admin());
