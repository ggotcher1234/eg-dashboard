-- 126_relink_resource_templates.sql   (9/24/26)
--
-- Greg (9/24/26): added a resource for every client, got "Resource added for
-- every client", and then -- "it does not show up in the preview or in the
-- client dashboard."
--
-- WHAT IS ACTUALLY WRONG
-- Adding an org-wide resource is two steps, and only the first one is done by
-- the app:
--   1. a row goes into resource_vault_templates  <- this worked, hence the
--      green message, and the resource IS on the Resource Vault templates page;
--   2. a row per client goes into client_resource_vault_items, pointing at that
--      template. This is done by the trigger in
--      029_auto_link_new_templates.sql, and it is the step that did not happen.
--
-- Everything client-facing reads step 2, never step 1 -- the Company Info
-- Resources list, the preview, and the client dashboard all read
-- client_resource_vault_items (get_client_public_view joins the template in
-- from there). So a template with no link rows exists, is listed on the
-- templates admin page, and appears nowhere else. Exactly what Greg is seeing.
--
-- The trigger fires on insert into resource_vault_templates and links the new
-- template to every client sharing its organization_id. Two things stop it:
--   * the trigger isn't on the table -- 029 was written 8/14/26 and these
--     migrations are applied by hand, so it may simply never have been run;
--   * or an organization_id mismatch -- the trigger only links clients whose
--     organization_id equals the template's, so a client created under a
--     different org (or with a null one) is skipped silently.
--
-- This migration reports which of the two it is, puts the trigger back, and
-- backfills every link that is missing -- including for templates added before
-- today. It changes no titles, no files and no existing rows; it only ADDS the
-- link rows that should already exist.
--
-- Safe to re-run: the second run finds nothing to add and says so.

-- ---------- 1. what the data looks like right now ----------
select
  (select count(*) from resource_vault_templates)                         as templates,
  (select count(*) from clients)                                          as clients,
  (select count(*) from client_resource_vault_items where template_id is not null) as template_links,
  (select count(*) from client_resource_vault_items where template_id is null)     as client_specific_rows,
  (select count(*) from pg_trigger
     where tgrelid = 'resource_vault_templates'::regclass
       and tgname  = 'trg_link_new_template')                             as trigger_present;

-- Templates that reach nobody -- the symptom, listed by name.
select t.id, t.title, t.created_at,
       (select count(*) from client_resource_vault_items i where i.template_id = t.id) as linked_clients
from resource_vault_templates t
order by linked_clients, t.created_at desc;

-- Organisations on each side. If a template's org appears here with no
-- clients, the mismatch is the cause rather than the missing trigger.
select 'templates' as side, organization_id, count(*) from resource_vault_templates group by 1,2
union all
select 'clients',           organization_id, count(*) from clients                  group by 1,2
order by 1,2;

-- ---------- 2. put the trigger back ----------
-- Identical to 029's, restated here so this file stands on its own.
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

-- ---------- 3. backfill the links that are missing ----------
-- Every (client, template) pair in the same organisation that has no row yet.
-- The not-exists guard is what makes this safe to re-run and safe to run on a
-- database where the trigger HAS been working -- it adds only what is absent.
--
-- sort_order comes from the template so a backfilled resource lands in the same
-- position for everyone, rather than at the bottom for some clients and the
-- middle for others.
do $$
declare
  n_added int;
  n_orphan int;
begin
  insert into client_resource_vault_items (client_id, template_id, sort_order)
  select c.id, t.id, t.sort_order
  from resource_vault_templates t
  join clients c on c.organization_id = t.organization_id
  where not exists (
    select 1 from client_resource_vault_items i
    where i.client_id = c.id and i.template_id = t.id
  );
  get diagnostics n_added = row_count;

  if n_added = 0 then
    raise notice 'Nothing to backfill -- every template already reaches every client in its organisation.';
  else
    raise notice 'Linked % missing template/client pairs.', n_added;
  end if;

  -- A template whose organisation has no clients at all cannot be fixed by the
  -- rule above; say so rather than let it look handled.
  select count(*) into n_orphan
  from resource_vault_templates t
  where not exists (select 1 from clients c where c.organization_id = t.organization_id);

  if n_orphan > 0 then
    raise notice
      '% template(s) belong to an organisation with no clients -- those cannot be linked by organisation and need looking at by hand.',
      n_orphan;
  end if;
end $$;

-- ---------- 4. confirm ----------
-- Expect every template to show the same linked_clients count, equal to the
-- number of clients in its organisation.
select t.title,
       (select count(*) from client_resource_vault_items i where i.template_id = t.id) as linked_clients
from resource_vault_templates t
order by t.sort_order, t.created_at;
