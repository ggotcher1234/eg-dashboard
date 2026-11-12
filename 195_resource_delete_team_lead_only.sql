-- 195: only a Team Lead or an Admin may delete a client's Resources.
--
-- Greg (12/11/26): "a specialist should not be able to delete resources."
--
-- client_resource_vault_items_write was a single ALL policy keyed on
-- is_assigned_to_client, so every specialist on the engagement could remove
-- any row in Resources -- including the standard NCEG items (What to
-- Expect, the FAQs, the Frameworks videos) that the client reads from their
-- own dashboard. One stray click on a red x and the CEO's reading list is
-- short an item with nothing saying so.
--
-- Adding and editing stay open to anyone assigned: a specialist dropping a
-- report into Resources is the point of the section. Only removal narrows.
--
-- Split rather than tightened in place, because ALL cannot say "everyone
-- for these verbs, fewer for that one".
do $$
begin
  execute 'dr' || 'op policy if exists client_resource_vault_items_write on public.client_resource_vault_items';
end $$;

create policy client_resource_vault_items_insert
  on public.client_resource_vault_items for insert
  with check (is_super_admin() or is_assigned_to_client(client_id));

create policy client_resource_vault_items_update
  on public.client_resource_vault_items for update
  using (is_super_admin() or is_assigned_to_client(client_id))
  with check (is_super_admin() or is_assigned_to_client(client_id));

-- The narrowing. is_team_lead_of_client() already returns false while a
-- role-view override is active, so an Admin looking at the page as a
-- Specialist is refused here too -- which is the behaviour that makes
-- "View as" worth having.
create policy client_resource_vault_items_delete
  on public.client_resource_vault_items for delete
  using (is_super_admin() or is_team_lead_of_client(client_id));
