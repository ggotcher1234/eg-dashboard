-- 081_evaluation_response_delete.sql
--
-- Depends on 078_evaluation_responses.sql (client_evaluation_responses).
--
-- Greg (8/25/26): "i just filled out a form for a client and i need to
-- delete it." 078 deliberately left client_evaluation_responses with no
-- insert/update/delete policy for anyone but the service-role Edge
-- Function (the public submit path has no session to gate), which also
-- meant there was no way for a Team Lead/Super Admin to clear out a test
-- submission from the app itself. This adds a delete policy scoped to
-- Super Admin only -- same restricted-delete pattern as team member
-- deletion (034) and client deletion elsewhere in this app -- and
-- client_profile.html gets a matching "Delete Response" button next to
-- "View Full Response".
--
-- Safe to re-run.

drop policy if exists "eval responses delete" on client_evaluation_responses;
create policy "eval responses delete" on client_evaluation_responses for delete
using (is_super_admin());
