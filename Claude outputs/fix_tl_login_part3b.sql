-- fix_tl_login_part3b.sql   (9/16/26)
--
-- Read-only. Changes nothing. Run the whole file.
--
-- Part 3 came back with every FK on auth.users set to CASCADE or SET NULL,
-- including `users, id, CASCADE`. So nothing hanging off auth.users is
-- blocking the delete, and my first guess was wrong.
--
-- What I missed: the cascade is a CHAIN. Deleting an auth.users row cascades
-- into public.users, and that second delete has children of its own. If any
-- of THOSE is NO ACTION or RESTRICT with rows attached, the whole delete
-- rolls back and Supabase reports "Database error deleting user" -- while
-- every constraint you can see on auth.users looks perfectly fine.
--
-- 046_assignments_fk_set_null.sql already fixed one of these
-- (client_assignments.user_id -> SET NULL). The question is which of the
-- others were never given a delete rule.
--
-- Part A finds them. Part B counts the rows actually in the way for this
-- specific account. Part C rules out a trigger, which is the other thing
-- that produces this error with no constraint to blame.


-- ---------------------------------------------------------------
-- PART A -- Everything that points at public.users, and its delete rule.
--
-- Any row marked "blocks delete" is a candidate. A table with a rule of
-- CASCADE or SET NULL can never be the cause.
-- ---------------------------------------------------------------
select
  con.conrelid::regclass::text  as child_table,
  att.attname                   as child_column,
  case con.confdeltype::text
    when 'a' then 'NO ACTION  <-- blocks delete'
    when 'r' then 'RESTRICT   <-- blocks delete'
    when 'c' then 'CASCADE'
    when 'n' then 'SET NULL'
    when 'd' then 'SET DEFAULT'
  end                           as on_delete
from pg_constraint con
join unnest(con.conkey) with ordinality as k(attnum, ord) on true
join pg_attribute att on att.attrelid = con.conrelid and att.attnum = k.attnum
where con.confrelid = 'public.users'::regclass
  and con.contype   = 'f'
  and con.conrelid <> 'public.users'::regclass
order by 3 desc, 1;


-- ---------------------------------------------------------------
-- PART B -- For the account you are trying to delete, how many rows sit in
-- each blocking table right now.
--
-- Walks the catalog, so a table nobody remembered is counted too. Only
-- tables whose delete rule would BLOCK are counted -- cascading ones will
-- clear themselves.
--
-- A completely empty result means nothing is in the way, and the delete is
-- failing for some other reason (see Part C).
-- ---------------------------------------------------------------
do $$
declare
  v_uid uuid := '023f54b5-6cdf-4742-bd3a-c230c5207222';  -- greg.gotcher@leadforcesolutions.com
  r     record;
  n     bigint;
  total bigint := 0;
begin
  if not exists (select 1 from public.users where id = v_uid) then
    raise notice 'No public.users row for this auth account at all.';
    raise notice 'Nothing can be blocking through public.users, and deleting';
    raise notice 'the auth user costs you no dashboard data. See Part C.';
    return;
  end if;

  for r in
    select con.conrelid::regclass::text as child_table,
           att.attname                  as child_column
    from pg_constraint con
    join unnest(con.conkey) with ordinality as k(attnum, ord) on true
    join pg_attribute att on att.attrelid = con.conrelid and att.attnum = k.attnum
    where con.confrelid = 'public.users'::regclass
      and con.contype = 'f'
      and con.conrelid <> 'public.users'::regclass
      and con.confdeltype::text in ('a', 'r')      -- NO ACTION / RESTRICT only
    order by 1
  loop
    execute format('select count(*) from %s where %I = $1', r.child_table, r.child_column)
      into n using v_uid;
    if n > 0 then
      raise notice 'BLOCKING  %.% -> % row(s)', r.child_table, r.child_column, n;
      total := total + n;
    end if;
  end loop;

  if total = 0 then
    raise notice 'Nothing blocking. No rows in any NO ACTION / RESTRICT child.';
  else
    raise notice '--- % row(s) total are holding this delete up.', total;
  end if;
end $$;


-- ---------------------------------------------------------------
-- PART C -- The other thing that causes this: a trigger.
--
-- A BEFORE/AFTER DELETE trigger on either table that raises will produce
-- the same opaque "Database error deleting user" with no constraint to
-- point at. Expect the handle_new_user-style INSERT triggers; a DELETE
-- trigger here is worth a second look.
-- ---------------------------------------------------------------
select
  tg.tgrelid::regclass::text as on_table,
  tg.tgname                  as trigger_name,
  case
    when (tg.tgtype::int & 4)  > 0 then 'INSERT'
    when (tg.tgtype::int & 8)  > 0 then 'DELETE'
    when (tg.tgtype::int & 16) > 0 then 'UPDATE'
    else 'other'
  end                        as fires_on,
  case when (tg.tgtype::int & 2) > 0 then 'BEFORE' else 'AFTER' end as timing,
  p.proname                  as function_name
from pg_trigger tg
join pg_proc p on p.oid = tg.tgfoid
where tg.tgrelid in ('auth.users'::regclass, 'public.users'::regclass)
  and not tg.tgisinternal
order by 1, 2;
