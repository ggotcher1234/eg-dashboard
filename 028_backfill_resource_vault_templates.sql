-- 028_backfill_resource_vault_templates.sql
--
-- Depends on 027_resource_vault_templates.sql.
--
-- 027 only links the 8 shared Resource Vault templates into clients
-- accepted AFTER it's applied (wired into accept_client_application()).
-- Existing clients -- like Test -- need the same 8 links added by hand.
--
-- For every (client, template) pair that isn't already linked, insert a
-- linked row. Clients that already have their own custom resources are
-- untouched -- this only adds the missing template links, alongside
-- whatever custom rows already exist.
--
-- Safe to re-run -- once a (client, template) pair is linked, it's
-- skipped on future runs.

insert into client_resource_vault_items (client_id, template_id, sort_order)
select c.id, rvt.id, rvt.sort_order
from clients c
join resource_vault_templates rvt on rvt.organization_id = c.organization_id
where not exists (
  select 1 from client_resource_vault_items existing
  where existing.client_id = c.id and existing.template_id = rvt.id
);
