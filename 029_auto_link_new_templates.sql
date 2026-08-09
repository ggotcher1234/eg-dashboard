-- 029_auto_link_new_templates.sql
--
-- Depends on 027_resource_vault_templates.sql.
--
-- 027 links a client's shared templates only at accept time; 028 backfilled
-- the initial 8 for already-accepted clients. But if a Super Admin adds a
-- NEW template later (from resource_templates.html) -- a 9th standard
-- resource, say -- it should show up for every existing client right away,
-- not just clients accepted after that point. This trigger does that: any
-- time a new resource_vault_templates row is inserted, it's auto-linked
-- into every existing client in that organization.

create or replace function link_new_template_to_existing_clients()
returns trigger
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
begin
  insert into client_resource_vault_items (client_id, template_id, sort_order)
  select c.id, new.id, new.sort_order
  from clients c
  where c.organization_id = new.organization_id;
  return new;
end;
$$;

drop trigger if exists trg_link_new_template on resource_vault_templates;
create trigger trg_link_new_template
  after insert on resource_vault_templates
  for each row
  execute function link_new_template_to_existing_clients();
