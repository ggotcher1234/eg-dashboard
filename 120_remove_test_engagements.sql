-- 120_remove_test_engagements.sql
--
-- Greg (9/16/26): "we are getting close to switching over to make this the
-- live system for EG. remove the test companies and their teams and hours
-- from the database and for now we'll just keep the ones that i am really
-- working on even though all the hours may not be perfect." Confirmed the
-- five to remove: everything outlined in red on the Engagements screen.
-- "everything is still being run out of podio so none of this data is real.
-- i just want to start trimming it down so that when we go live we don't
-- have a bunch of junk in the database."
--
-- THIS DELETES DATA AND CANNOT BE UNDONE. Run PART 1 on its own first and
-- read what it prints. PART 2 does the deleting and is written to refuse
-- rather than guess -- see the two guards in it.
--
-- REMOVES (5 engagements, with everything hanging off them):
--   Test                   (Alloy Development)
--   Excaliber              (Annapolis)
--   First Class Funding    (Economic Development Partnership of North Carolina)
--   Gee Whiz Products      (Greater Rochester Enterprise)
--   The Best Coffee        (Test 2 Company)
--
-- KEEPS: Clippard Instrument Labs, JCS Process & Controls Inc., Extremis
-- Systems, JLR Environmental -- and every Program, including the now-empty
-- Test 2 Company. Programs were not part of what Greg confirmed; the
-- Programs screen can archive that one in a click.
--
-- NOT touched, on purpose:
--   * Program invoices. program_invoices references econ_dev_companies, not
--     clients -- an engagement's numbers live inside its line_items jsonb, a
--     snapshot of what was billed. Deleting an engagement does not rewrite
--     history, and rewriting it here would be worse.
--   * Files in Storage. Rows in `documents` go, but the uploaded objects sit
--     in a Storage bucket that SQL here does not reach. PART 1 lists their
--     paths so they can be cleared from the Storage browser if wanted;
--     leaving them costs nothing but space.

-- =====================================================================
-- PART 1 -- PREVIEW. Read-only. Run this alone, first.
-- =====================================================================

-- 1a. Exactly which engagements match? Expect 5 rows and no more.
select
  c.id,
  c.name,
  coalesce(p.name, '(no Program)') as program,
  c.project_status,
  c.created_at::date as created
from clients c
left join econ_dev_companies p on p.id = c.econ_dev_company_id
where c.name in (
  'Test',
  'Excaliber',
  'First Class Funding',
  'Gee Whiz Products',
  'The Best Coffee'
)
order by c.name;

-- 1b. What hangs off them? One row per table that points at clients, with
--     the number of rows that will go with the delete. Reads the catalog
--     rather than a hand-written list, so a table nobody remembered still
--     shows up here.
do $$
declare
  r record;
  n bigint;
  v_ids uuid[];
begin
  select array_agg(id) into v_ids from clients where name in (
    'Test', 'Excaliber', 'First Class Funding', 'Gee Whiz Products', 'The Best Coffee');

  raise notice '--- rows that will be deleted along with the 5 engagements ---';
  for r in
    select con.conrelid::regclass::text as child_table,
           att.attname                  as child_column,
           con.confdeltype::text        as on_delete
    from pg_constraint con
    join unnest(con.conkey) with ordinality as k(attnum, ord) on true
    join pg_attribute att on att.attrelid = con.conrelid and att.attnum = k.attnum
    where con.confrelid = 'clients'::regclass
      and con.contype = 'f'
    order by 1
  loop
    execute format('select count(*) from %s where %I = any($1)', r.child_table, r.child_column)
      into n using v_ids;
    raise notice '% .% : % row(s)   [on delete %]',
      r.child_table, r.child_column, n,
      case r.on_delete when 'c' then 'CASCADE' when 'n' then 'SET NULL'
                       when 'a' then 'NO ACTION' when 'r' then 'RESTRICT'
                       when 'd' then 'SET DEFAULT' else r.on_delete end;
  end loop;
end $$;

-- 1c. Hours specifically -- the part Greg named. Time entries reach a client
--     through client_assignments, so they are worth their own count.
select
  c.name                          as engagement,
  count(distinct a.id)            as team_slots,
  count(t.id)                     as time_entries,
  coalesce(sum(t.hours), 0)       as hours_logged
from clients c
left join client_assignments a on a.client_id = c.id
left join time_entries t on t.assignment_id = a.id
where c.name in ('Test', 'Excaliber', 'First Class Funding', 'Gee Whiz Products', 'The Best Coffee')
group by c.name
order by c.name;

-- 1d. Uploaded files that will lose their database row. SQL cannot delete
--     the objects themselves -- copy these paths if they should be cleared
--     from Storage too.
select c.name as engagement, d.file_name, d.storage_path
from documents d
join clients c on c.id = d.client_id
where c.name in ('Test', 'Excaliber', 'First Class Funding', 'Gee Whiz Products', 'The Best Coffee')
  and d.storage_path is not null
order by c.name, d.file_name;


-- =====================================================================
-- PART 2 -- THE DELETE. Run only after PART 1 looks right.
-- =====================================================================
--
-- Two guards, both of which abort the whole thing rather than do something
-- approximate:
--
--   1. The five names must match exactly five rows. If a name was renamed,
--      or something real happens to share a name, the count is wrong and
--      nothing is deleted.
--   2. Every foreign key pointing at clients must be ON DELETE CASCADE.
--      This is what makes one delete safe: without it a child row would
--      either block the delete or be left orphaned pointing at a client
--      that no longer exists. If a table is found that does not cascade,
--      this stops and names it, so it can be handled deliberately.
--
-- It runs as one transaction: any failure rolls the whole thing back.

begin;

do $$
declare
  v_ids   uuid[];
  v_count int;
  v_bad   text;
begin
  select array_agg(id), count(*) into v_ids, v_count
  from clients
  where name in ('Test', 'Excaliber', 'First Class Funding', 'Gee Whiz Products', 'The Best Coffee');

  -- Guard 1: exactly the five, no more, no fewer.
  if v_count is distinct from 5 then
    raise exception
      'Expected exactly 5 engagements to delete, found %. Nothing deleted -- check PART 1a.', coalesce(v_count, 0);
  end if;

  -- Guard 2: nothing points at clients without cascading.
  select string_agg(format('%s.%I', con.conrelid::regclass, att.attname), ', ')
    into v_bad
  from pg_constraint con
  join unnest(con.conkey) with ordinality as k(attnum, ord) on true
  join pg_attribute att on att.attrelid = con.conrelid and att.attnum = k.attnum
  where con.confrelid = 'clients'::regclass
    and con.contype = 'f'
    and con.confdeltype <> 'c';

  if v_bad is not null then
    raise exception
      'These reference clients without ON DELETE CASCADE: %. Nothing deleted -- clear them first.', v_bad;
  end if;

  delete from clients where id = any(v_ids);
  raise notice 'Deleted % engagements and everything that cascaded from them.', v_count;
end $$;

commit;


-- =====================================================================
-- Verify. Expect the five to be gone and the four keepers to remain.
-- =====================================================================
select
  coalesce(p.name, '(no Program)') as program,
  c.name                          as engagement,
  c.project_status
from clients c
left join econ_dev_companies p on p.id = c.econ_dev_company_id
order by 1, 2;

-- Any Program now holding no engagements at all -- Test 2 Company should be
-- among them. Archive from the Programs screen if wanted; nothing here does.
select p.name as program_with_no_engagements
from econ_dev_companies p
where not p.archived
  and not exists (select 1 from clients c where c.econ_dev_company_id = p.id)
order by p.name;
