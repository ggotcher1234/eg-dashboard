-- run_now_remove_clippard_gis_hours.sql   (9/18/26)
--
-- Greg: "we were playing in the sandbox when we added 8 GIS hours for Amjad.
-- then removed him. those 8 hours need to go away."
--
-- One time entry, identified by id rather than by description:
--
--   id            523defed-f93f-4188-aef0-2ffe5ef5384b
--   8 hours, 2026-08-11, logged by Amjad Syed
--   on Clippard Instrument Labs / GIS (assignment a82aed9e-...), a row that
--   now has nobody on it and 0 allotted hours
--
-- This is the row behind two things you have seen this week: the 8 hours that
-- were silently missing from the invoice before the attribution fix, and the
-- "Hours logged by Amjad Syed" note added today. Both were working correctly --
-- they were faithfully reporting a test.
--
-- IRREVERSIBLE, and it is real logged time as far as the database is
-- concerned, so the delete is guarded three ways:
--   * it matches on the id, not on hours or a date
--   * it refuses unless that row still looks exactly as described above
--     (8 hours, Amjad, that GIS assignment) -- if anything has changed since
--     this file was written, it stops and tells you rather than guessing
--   * it refuses if it would remove more than one row
--
-- Deletes nothing else. The GIS assignment row stays, unassigned with 0 hours,
-- ready for whoever picks the work area up.
--
-- Safe to re-run: the second run finds nothing and says so.

do $$
declare
  v_entry uuid := '523defed-f93f-4188-aef0-2ffe5ef5384b';
  v_asg   uuid := 'a82aed9e-aacb-418f-9dc2-1d629693902d';
  r       record;
  n       int;
begin
  select t.id, t.hours, t.entry_date, t.assignment_id, u.full_name, c.name as client
    into r
  from time_entries t
  left join users u            on u.id = t.consultant_id
  left join client_assignments a on a.id = t.assignment_id
  left join clients c          on c.id = a.client_id
  where t.id = v_entry;

  if not found then
    raise notice 'Already gone -- no time entry with that id. Nothing to do.';
    return;
  end if;

  if r.hours <> 8 or r.assignment_id <> v_asg or coalesce(r.full_name, '') <> 'Amjad Syed' then
    raise exception
      'Stopping -- that entry is not what this file expects (found % h by % on %). Nothing was deleted.',
      r.hours, coalesce(r.full_name, '(nobody)'), r.client;
  end if;

  delete from time_entries where id = v_entry;
  get diagnostics n = row_count;

  if n <> 1 then
    raise exception 'Expected to delete exactly 1 row, deleted %. Rolled back.', n;
  end if;

  raise notice 'Deleted % h logged by % on % / GIS.', r.hours, r.full_name, r.client;
end $$;

-- Expect: the GIS row at 0 spent, and 10 time entries left in the system
-- (was 11).
select
  c.name                                   as engagement,
  a.specialty_type::text                   as work_area,
  coalesce(u.full_name, 'not assigned')    as person,
  a.hours_allotted                         as allotted,
  coalesce(sum(t.hours), 0)                as spent
from client_assignments a
join clients c            on c.id = a.client_id
left join users u         on u.id = a.user_id
left join time_entries t  on t.assignment_id = a.id
where a.id = 'a82aed9e-aacb-418f-9dc2-1d629693902d'
group by c.name, a.specialty_type, u.full_name, a.hours_allotted;

select count(*) as time_entries_remaining from time_entries;
