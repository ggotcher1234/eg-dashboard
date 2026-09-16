-- 122_remove_company_test_engagements.sql   (applied 9/16/26)
--
-- Follows 120_remove_test_engagements.sql, which cleaned out five test
-- engagements on the same principle and missed these two.
--
-- Greg: deleting the duplicate Steven Groves is blocked -- "he has no assigned
-- hours in current engagements but must have some in a table somewhere from
-- previous tests."
--
-- WHAT IS ACTUALLY BLOCKING IT
-- Not hours. Neither Steven Groves row has a single time entry. The block is
-- one client_assignments row each, both on engagements created 8/15/26:
--
--   sgroves@socialmarketingconversations.com  digital_marketing on "Company Challenges"
--   steven@socialmarketingconversations.com   team_lead         on "Company Info"
--
-- "Company Challenges" and "Company Info" are not companies. They are the
-- headings off the application form, submitted as the company name during a
-- test. Each one built a full 7-row engagement. 120_remove_test_engagements.sql
-- cleaned out five test engagements and these two were not on its list.
--
-- So this is not a Steven problem. It is two pieces of test data still sitting
-- in the Engagements screen five weeks later, and removing them clears the
-- delete block as a side effect -- on BOTH Steven rows, and on anyone else
-- those 14 assignment rows happen to name.
--
-- Same one-statement shape as 120, which worked: it clears child rows by
-- reading the foreign keys out of the catalog, so a table nobody remembered is
-- handled too, whatever its delete rule says.
--
-- IRREVERSIBLE. It removes these two engagements and everything attached --
-- assignments, contacts, documents, research, notifications.
--
-- IT REFUSES IF IT FINDS LOGGED HOURS. There are none as of today, so expect
-- it to proceed. If someone logs hours against either one between now and when
-- you run this, it stops and prints them rather than erasing real work.
--
-- Keeps Clippard, Extremis, JCS, JLR and EG Training. Safe to re-run: the
-- second run finds nothing and says so.

do $$
declare
  v_names text[] := array['Company Challenges', 'Company Info'];
  v_ids     uuid[];
  v_found   text;
  v_hours   text;
  r         record;
  n         bigint;
  total     bigint := 0;
begin
  select array_agg(c.id), string_agg(c.name, ', ' order by c.name)
    into v_ids, v_found
  from clients c
  where lower(btrim(c.name)) = any (select lower(btrim(x)) from unnest(v_names) x);

  if v_ids is null then
    raise notice 'Nothing to delete -- neither name is in clients. Already removed?';
    return;
  end if;

  -- Safety gate. Assignments are disposable; logged hours are somebody's work.
  select string_agg(format('%s %s h on %s', t.entry_date, t.hours, c.name), '; ' order by t.entry_date)
    into v_hours
  from time_entries t
  join client_assignments a on a.id = t.assignment_id
  join clients c            on c.id = a.client_id
  where a.client_id = any (v_ids);

  if v_hours is not null then
    raise exception
      'Stopping -- these engagements have logged hours: %. Nothing was deleted. Send me this message.', v_hours;
  end if;

  raise notice 'Deleting: % (no logged hours found)', v_found;

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
-- What is left. Expect five engagements, and both Steven Groves rows
-- showing 0 assignments and 0 hours -- meaning the duplicate will now delete
-- from the Roster screen.
-- ---------------------------------------------------------------
select
  coalesce(p.name, '(no Program)') as program,
  c.name                          as engagement,
  c.project_status
from clients c
left join econ_dev_companies p on p.id = c.econ_dev_company_id
order by 1, 2;

select
  u.full_name,
  u.email,
  u.role::text                                    as eg_role,
  count(distinct a.id)                            as assignments,
  count(distinct t.id)                            as hours_logged,
  case when count(distinct a.id) = 0 and count(distinct t.id) = 0
       then 'clear -- the X on the Roster will work'
       else 'still blocked' end                   as delete_status
from users u
left join client_assignments a on a.user_id = u.id
left join time_entries       t on t.consultant_id = u.id
where u.full_name ilike '%Groves%'
group by u.full_name, u.email, u.role
order by u.email;
