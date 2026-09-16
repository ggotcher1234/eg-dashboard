-- 120_remove_test_engagements.sql  (revised 9/16/26)
--
-- Greg: "remove the test companies and their teams and hours from the
-- database" -> then, after the first version: "they still seem to be there.
-- i want them erased from the engagement screen."
--
-- WHY THE FIRST VERSION MAY NOT HAVE DELETED ANYTHING
-- It was written as two parts with a `begin; ... commit;` around the delete,
-- and it refused to run at all if any table referenced clients without
-- ON DELETE CASCADE. Either of those can leave everything untouched:
--   * running only PART 1 (which is read-only) does nothing by design;
--   * the Supabase SQL editor commits statement by statement, so a stray
--     begin/commit is easy to half-run;
--   * and one non-cascading table anywhere would abort the whole thing.
--
-- This version removes all three failure modes. It is ONE statement. It
-- clears child rows itself rather than depending on cascade, so it works
-- whatever the foreign keys say. Select all of it, run it, and read the
-- Messages/Notices pane -- it reports what it deleted, by name.
--
-- STILL IRREVERSIBLE. It removes these five engagements and everything
-- attached to them -- team assignments, logged hours, contacts, documents,
-- research, notifications:
--
--   Test, Excaliber, First Class Funding, Gee Whiz Products, The Best Coffee
--
-- Keeps Clippard Instrument Labs, JCS Process & Controls Inc., Extremis
-- Systems, JLR Environmental, and every Program.
--
-- Safe to re-run: the second run finds nothing and says so.

do $$
declare
  v_names text[] := array[
    'Test',
    'Excaliber',
    'First Class Funding',
    'Gee Whiz Products',
    'The Best Coffee'
  ];
  v_ids     uuid[];
  v_found   text;
  v_missing text;
  r         record;
  n         bigint;
  total     bigint := 0;
begin
  -- Which of the five actually exist right now (trimmed + case-insensitive,
  -- so a stray space or capital in the data cannot silently skip one).
  select array_agg(c.id), string_agg(c.name, ', ' order by c.name)
    into v_ids, v_found
  from clients c
  where lower(btrim(c.name)) = any (select lower(btrim(x)) from unnest(v_names) x);

  if v_ids is null then
    raise notice 'Nothing to delete -- none of those five names are in clients. Already removed?';
    return;
  end if;

  select string_agg(x, ', ') into v_missing
  from unnest(v_names) x
  where lower(btrim(x)) not in (select lower(btrim(c.name)) from clients c);

  raise notice 'Deleting: %', v_found;
  if v_missing is not null then
    raise notice 'Not found (skipped): %', v_missing;
  end if;

  -- Clear child rows explicitly, every table that points at clients,
  -- whatever its delete rule. Cascading tables will already be empty by the
  -- time the client row goes; non-cascading ones would otherwise block the
  -- delete or be left orphaned. Reading the catalog means a table nobody
  -- remembered is handled too.
  for r in
    select con.conrelid::regclass::text as child_table,
           att.attname                  as child_column
    from pg_constraint con
    join unnest(con.conkey) with ordinality as k(attnum, ord) on true
    join pg_attribute att on att.attrelid = con.conrelid and att.attnum = k.attnum
    where con.confrelid = 'clients'::regclass
      and con.contype = 'f'
      and con.conrelid <> 'clients'::regclass
    order by 1
  loop
    execute format('delete from %s where %I = any($1)', r.child_table, r.child_column)
      using v_ids;
    get diagnostics n = row_count;
    if n > 0 then
      raise notice '  %: % row(s)', r.child_table, n;
      total := total + n;
    end if;
  end loop;

  delete from clients where id = any(v_ids);
  get diagnostics n = row_count;
  raise notice 'Done: % engagement(s) removed, plus % related row(s).', n, total;
end $$;


-- ---------------------------------------------------------------
-- What is left. Expect only the four keepers.
-- ---------------------------------------------------------------
select
  coalesce(p.name, '(no Program)') as program,
  c.name                          as engagement,
  c.project_status
from clients c
left join econ_dev_companies p on p.id = c.econ_dev_company_id
order by 1, 2;
