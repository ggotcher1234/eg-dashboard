-- 198: reordering the default Resource list, and carrying that order to
-- engagements that have not arranged their own.
--
-- Greg (19/11/26): "i need to be able to modify the order of the resources
-- in the vault." The per-engagement vault has had drag-to-reorder since
-- 9/26; the defaults page could only append, so the order was whatever
-- order things were added in.
--
-- WHY A FUNCTION AND NOT SIX UPDATES FROM THE PAGE
-- A template's order lives in two places. resource_vault_templates.sort_order
-- is the default, and every engagement holds its own row in
-- client_resource_vault_items with its own sort_order -- which is what makes
-- a Team Lead's drag on one client stay on that client. Changing only the
-- template would reorder nothing anybody can see today, because every
-- existing engagement already carries its own copy of the old numbers.
--
-- So this does both, in one transaction, with one rule: an engagement's row
-- moves only if it was still sitting at the template's OLD position. A list
-- somebody has deliberately dragged has expressed a preference, and a change
-- to the house default is not a reason to overrule it.
create or replace function public.reorder_resource_templates(p_ids uuid[])
returns void
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  org_id uuid;
begin
  if not is_super_admin() then
    raise exception 'Only an Admin can reorder the default Resources';
  end if;

  select organization_id into org_id
  from resource_vault_templates
  where id = p_ids[1];
  if org_id is null then
    raise exception 'Unknown resource template';
  end if;

  -- Refuse a partial list. Writing positions from an array that is missing a
  -- row would leave that row's number colliding with another's.
  if (select count(*) from resource_vault_templates where organization_id = org_id)
     <> coalesce(array_length(p_ids, 1), 0) then
    raise exception 'The list of resources is out of date -- reload the page and try again';
  end if;

  -- old position -> new position, before anything is written
  create temp table _reorder on commit drop as
  select t.id,
         t.sort_order as old_order,
         (array_position(p_ids, t.id) - 1) as new_order
  from resource_vault_templates t
  where t.organization_id = org_id;

  update client_resource_vault_items i
  set sort_order = r.new_order
  from _reorder r
  where i.template_id = r.id
    and i.sort_order is not distinct from r.old_order;

  update resource_vault_templates t
  set sort_order = r.new_order
  from _reorder r
  where t.id = r.id;
end;
$fn$;

revoke all on function public.reorder_resource_templates(uuid[]) from public;
grant execute on function public.reorder_resource_templates(uuid[]) to authenticated;
