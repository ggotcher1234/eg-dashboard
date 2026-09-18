-- run_now_fix_clippard_mr_hours.sql   (9/18/26)
--
-- Greg: the Arlene / Kelly split on Clippard's Market Research row was sandbox
-- play too -- credit the hours to Kelly, who holds the row.
--
-- One time entry, by id:
--
--   id          d41f9463-ce45-4d8e-af67-31796f4d5c26
--   3 hours, 2026-08-11, on Clippard Instrument Labs / Market Research
--   consultant_id  Arlene Goldhammer  ->  Kelly Berry
--
-- This is an UPDATE, not a delete: the hours are real, only the name on them
-- was the test. Clippard stays at 36 allotted / 20 spent. What changes is that
-- Team & Hours stops showing "Hours logged by Arlene Goldhammer" under Kelly,
-- and the cumulative report and pay statements credit the 3 hours to Kelly
-- rather than splitting Market Research across two people.
--
-- Guarded the same way as the GIS delete:
--   * matches on the entry id, not on hours or a date
--   * refuses unless that row is still 3 hours currently attributed to Arlene
--     on that assignment -- if anything has moved since, it stops and says so
--   * refuses if it would touch more than one row
--
-- Safe to re-run: once the entry is Kelly's, the second run says so and stops.

do $$
declare
  v_entry  uuid := 'd41f9463-ce45-4d8e-af67-31796f4d5c26';
  v_asg    uuid := '868079c6-2fcd-4c71-a4ac-8b40eabfe0c6';
  v_arlene uuid := 'ddb2bbd2-b676-4013-9e9c-8d29c27dcbb4';
  v_kelly  uuid := '0fc39c92-9378-43de-87bd-74487773af45';
  r        record;
  n        int;
begin
  select t.id, t.hours, t.consultant_id, t.assignment_id, u.full_name, c.name as client
    into r
  from time_entries t
  left join users u              on u.id = t.consultant_id
  left join client_assignments a on a.id = t.assignment_id
  left join clients c            on c.id = a.client_id
  where t.id = v_entry;

  if not found then
    raise exception 'No time entry with that id. Nothing was changed.';
  end if;

  if r.consultant_id = v_kelly then
    raise notice 'Already credited to Kelly Berry. Nothing to do.';
    return;
  end if;

  if r.hours <> 3 or r.assignment_id <> v_asg or r.consultant_id <> v_arlene then
    raise exception
      'Stopping -- that entry is not what this file expects (found % h by % on %). Nothing was changed.',
      r.hours, coalesce(r.full_name, '(nobody)'), r.client;
  end if;

  update time_entries set consultant_id = v_kelly where id = v_entry;
  get diagnostics n = row_count;

  if n <> 1 then
    raise exception 'Expected to update exactly 1 row, updated %. Rolled back.', n;
  end if;

  raise notice 'Moved % h on % / Market Research from Arlene Goldhammer to Kelly Berry.', r.hours, r.client;
end $$;

-- Expect: Market Research held by Kelly, 6 allotted, 3 spent, and the hours
-- now logged by Kelly -- so nothing left for the "Hours logged by" note to say.
select
  c.name                                as engagement,
  a.specialty_type::text                as work_area,
  coalesce(h.full_name, 'not assigned') as row_held_by,
  coalesce(l.full_name, '(none)')       as hours_logged_by,
  a.hours_allotted                      as allotted,
  coalesce(sum(t.hours), 0)             as spent
from client_assignments a
join clients c             on c.id = a.client_id
left join users h          on h.id = a.user_id
left join time_entries t   on t.assignment_id = a.id
left join users l          on l.id = t.consultant_id
where a.id = '868079c6-2fcd-4c71-a4ac-8b40eabfe0c6'
group by c.name, a.specialty_type, h.full_name, l.full_name, a.hours_allotted;

-- And the engagement total, unchanged at 20 spent.
select
  coalesce(sum(t.hours), 0) as clippard_hours_logged
from client_assignments a
join clients c           on c.id = a.client_id
left join time_entries t on t.assignment_id = a.id
where c.name like 'Clippard%';
