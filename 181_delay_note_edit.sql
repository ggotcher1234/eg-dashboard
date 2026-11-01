-- 181: let a Team Lead edit their own overdue comment in place.
--
-- Greg (11/1/26): "the Overdue comment needs to be editable here on the
-- engagements page by the team lead."
--
-- client_delay_notes had insert / select / delete policies but no update, so
-- fixing a word meant deleting the comment and writing it again -- which
-- threw away the date it was first given, the one thing the dialog orders
-- and labels by. edited_at records that a comment was changed without
-- disturbing created_at.
--
-- Same rule as the delete policy: your own comment, or anything if you are
-- an Admin. Editing somebody else's explanation of why their engagement is
-- late is not a thing a Team Lead should be able to do.

alter table public.client_delay_notes
  add column if not exists edited_at timestamptz;

drop policy if exists client_delay_notes_update on public.client_delay_notes;

create policy client_delay_notes_update on public.client_delay_notes
  for update
  using (is_super_admin() or author_id = auth.uid())
  with check (is_super_admin() or author_id = auth.uid());
