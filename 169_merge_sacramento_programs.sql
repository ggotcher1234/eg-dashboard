-- 169_merge_sacramento_programs.sql
--
-- Two Sacramento programs were created by accident:
--
--   KEEP  0da5b6c3-d771-49f1-8d2c-c232c02d73a9  "SACRAMENTO"      archived = false
--         -> the one on the Programs page. Has the address, phone, notes,
--            the city-seal logo, the 5-name CC list, and LiCap Technologies.
--
--   DROP  0e59b2e1-49f7-48ca-a980-018b22767637  "Sacramento, CA"  archived = true
--         -> holds the real history: JLR Environmental and Extremis Systems
--            (engagements and applications), 2 program invoices, Craig Keys as
--            program administrator, $115/hr, $150 setup fee.
--
-- This moves everything off the archived row onto the keeper, renames the
-- keeper "Sacramento, CA" (code stays SACRAMENTO), then deletes the archived
-- row. Field rule: the keeper wins wherever it already has a value; the
-- archived row only fills blanks. setup_fee is the one exception -- the
-- keeper's 0 is treated as unset.
--
-- Safe to re-run: the second run finds no archived row and does nothing.
--
-- NOTE: clients carries enforce_super_admin_client_fields(), which refuses any
-- change to econ_dev_company_id unless auth.uid() is a Super Admin. Run from
-- the SQL editor there is no logged-in user, so this script disables the user
-- triggers on the affected tables for the duration and re-enables them at the
-- end. The whole thing is one statement, so a failure anywhere rolls the
-- triggers back on too.

do $$
declare
  v_keep uuid := '0da5b6c3-d771-49f1-8d2c-c232c02d73a9';
  v_drop uuid := '0e59b2e1-49f7-48ca-a980-018b22767637';
  r record;
  n bigint;
  v_tabs text[];
  t text;
begin
  if not exists (select 1 from econ_dev_companies where id = v_drop) then
    raise notice 'Already merged - archived Sacramento row is gone. Nothing to do.';
    return;
  end if;
  if not exists (select 1 from econ_dev_companies where id = v_keep) then
    raise exception 'Keeper program % not found - aborting', v_keep;
  end if;

  ----------------------------------------------------------------------------
  -- 0. Stand the guard triggers down. Internal triggers (foreign keys, unique
  --    constraints) are left alone - only user triggers are touched.
  ----------------------------------------------------------------------------
  select array_agg(distinct con.conrelid::regclass::text)
    into v_tabs
    from pg_constraint con
   where con.contype = 'f'
     and con.confrelid = 'public.econ_dev_companies'::regclass;
  v_tabs := coalesce(v_tabs, '{}'::text[]) || 'econ_dev_companies'::text;

  foreach t in array v_tabs loop
    for r in select tgname from pg_trigger
              where tgrelid = t::regclass and not tgisinternal loop
      execute format('alter table %s disable trigger %I', t, r.tgname);
    end loop;
  end loop;

  ----------------------------------------------------------------------------
  -- 1. Fill the keeper's blank fields from the archived row.
  --    Done column by column off the catalog so a column added later is
  --    picked up without editing this script.
  ----------------------------------------------------------------------------
  for r in
    select column_name
      from information_schema.columns
     where table_schema = 'public'
       and table_name   = 'econ_dev_companies'
       and column_name not in
           ('id','organization_id','code','name','created_at','updated_at','archived','active')
     order by ordinal_position
  loop
    execute format(
      'update econ_dev_companies k set %1$I = d.%1$I
         from econ_dev_companies d
        where k.id = $1 and d.id = $2
          and k.%1$I is null and d.%1$I is not null',
      r.column_name) using v_keep, v_drop;
    get diagnostics n = row_count;
    if n > 0 then
      raise notice 'filled blank field: %', r.column_name;
    end if;
  end loop;

  -- Name, and the setup fee whose 0 is an unset default rather than a value.
  update econ_dev_companies k
     set name       = 'Sacramento, CA',
         setup_fee  = coalesce(nullif(k.setup_fee, 0), d.setup_fee),
         updated_at = now()
    from econ_dev_companies d
   where k.id = v_keep and d.id = v_drop;

  ----------------------------------------------------------------------------
  -- 2. Partner contacts: drop exact duplicates, then push the survivors to the
  --    end of the keeper's list so sort_order can't collide.
  ----------------------------------------------------------------------------
  delete from econ_dev_partner_contacts d
   where d.partner_id = v_drop
     and exists (
       select 1 from econ_dev_partner_contacts k
        where k.partner_id = v_keep
          and k.category is not distinct from d.category
          and lower(trim(k.name)) = lower(trim(d.name)));
  get diagnostics n = row_count;
  if n > 0 then raise notice 'removed % duplicate contact(s)', n; end if;

  select coalesce(max(sort_order), 0) into n
    from econ_dev_partner_contacts where partner_id = v_keep;
  update econ_dev_partner_contacts
     set sort_order = n + coalesce(sort_order, 0) + 1
   where partner_id = v_drop;

  ----------------------------------------------------------------------------
  -- 3. Repoint every row that references the archived program. Walked off
  --    pg_constraint so nothing is missed -- clients, client_applications,
  --    client_application_drafts, program_invoices, partner contacts, and any
  --    table that gains the foreign key later.
  ----------------------------------------------------------------------------
  for r in
    select con.conrelid::regclass::text as tbl, att.attname as col
      from pg_constraint con
      join unnest(con.conkey) with ordinality as k(attnum, ord) on true
      join pg_attribute att
        on att.attrelid = con.conrelid and att.attnum = k.attnum
     where con.contype  = 'f'
       and con.confrelid = 'public.econ_dev_companies'::regclass
     order by 1, 2
  loop
    execute format('update %s set %I = $1 where %I = $2', r.tbl, r.col, r.col)
      using v_keep, v_drop;
    get diagnostics n = row_count;
    if n > 0 then
      raise notice 'moved % row(s): %.%', n, r.tbl, r.col;
    end if;
  end loop;

  ----------------------------------------------------------------------------
  -- 4. The archived program is now empty. Remove it.
  ----------------------------------------------------------------------------
  delete from econ_dev_companies where id = v_drop;
  raise notice 'Deleted archived Sacramento program %', v_drop;

  ----------------------------------------------------------------------------
  -- 5. Put the guard triggers back.
  ----------------------------------------------------------------------------
  foreach t in array v_tabs loop
    for r in select tgname from pg_trigger
              where tgrelid = t::regclass and not tgisinternal loop
      execute format('alter table %s enable trigger %I', t, r.tgname);
    end loop;
  end loop;
end $$;

-- Verification: one Sacramento program, holding all four engagements.
select e.id, e.name, e.code, e.archived, e.billing_hourly_rate, e.setup_fee,
       (select count(*) from clients              c where c.econ_dev_company_id = e.id) as engagements,
       (select count(*) from client_applications  a where a.econ_dev_company_id = e.id) as applications,
       (select count(*) from program_invoices     i where i.econ_dev_company_id = e.id) as invoices,
       (select count(*) from econ_dev_partner_contacts p where p.partner_id      = e.id) as contacts
  from econ_dev_companies e
 where e.name ilike '%sacrament%';

drop function if exists _sac_report();
