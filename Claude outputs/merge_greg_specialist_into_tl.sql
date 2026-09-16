-- merge_greg_specialist_into_tl.sql   (9/16/26)
--
-- Moves Greg's engagement work off the consultant login and onto the Team
-- Lead login, so one login shows everything he is on -- as Team Lead on some
-- engagements and as a specialist on others, which is how every other Team
-- Lead will work.
--
--   FROM  greggotcher@gmail.com               (consultant)  -- JCS, JLR
--   TO    greg.gotcher@leadforcesolutions.com (team_lead)   -- Clippard, Extremis
--
-- Afterwards the gmail account keeps its login and its consultant role but
-- has no engagements on it: a clean empty Specialist, useful for recording
-- the Specialist training video and for checking role gating without
-- borrowing somebody else's screen.
--
-- WHAT MOVES
--   client_assignments.user_id        the engagements themselves
--   time_entries.consultant_id        the hours already logged against them
--
-- Both, together, or not at all. Moving assignments without hours would leave
-- every Spent number on JCS and JLR pointing at a person who is no longer on
-- the team, and the workspace's "this is your row" test would stop matching.
--
-- WHAT DOES NOT MOVE
-- Historical attribution -- who uploaded a document, who submitted an
-- application, who a past notification was addressed to. Those are records of
-- something that happened, not live state, and rewriting them would make the
-- audit trail say something that is not true.
--
-- SAFE TO RE-RUN. The second run finds nothing to move and says so.
-- ONE statement, so it either all happens or none of it does -- which matters
-- in the Supabase editor, where separate statements commit one at a time.

do $$
declare
  v_from_email text := 'greggotcher@gmail.com';
  v_to_email   text := 'greg.gotcher@leadforcesolutions.com';
  v_from uuid;
  v_to   uuid;
  v_clash int;
  n_assign int;
  n_hours  int;
  r record;
begin
  select id into v_from from public.users
   where id = (select id from auth.users where email = v_from_email);
  select id into v_to   from public.users
   where id = (select id from auth.users where email = v_to_email);

  if v_from is null then
    raise exception 'No EG Dashboard profile for % -- nothing done.', v_from_email;
  end if;
  if v_to is null then
    raise exception 'No EG Dashboard profile for % -- nothing done.', v_to_email;
  end if;
  if v_from = v_to then
    raise exception 'Those are the same account -- nothing done.';
  end if;

  ----------------------------------------------------------------
  -- Preview, before anything changes.
  ----------------------------------------------------------------
  for r in
    select c.name, a.specialty_type, a.slot_number, a.is_team_lead
    from public.client_assignments a
    join public.clients c on c.id = a.client_id
    where a.user_id = v_from
    order by c.name
  loop
    raise notice 'MOVING  % -- % (slot %)%',
      r.name, r.specialty_type, r.slot_number,
      case when r.is_team_lead then ' [Team Lead]' else '' end;
  end loop;

  ----------------------------------------------------------------
  -- Refuse if both accounts occupy the same slot on the same engagement.
  -- client_assignments is one row per (engagement, specialty, slot); merging
  -- two people into one could collide there, and a silent constraint error
  -- mid-merge is the worst outcome. Check first.
  ----------------------------------------------------------------
  select count(*) into v_clash
  from public.client_assignments a
  join public.client_assignments b
    on  b.client_id      = a.client_id
    and b.specialty_type = a.specialty_type
    and b.slot_number    = a.slot_number
  where a.user_id = v_from
    and b.user_id = v_to;

  if v_clash > 0 then
    raise exception
      'Both accounts hold the same slot on % engagement(s). Sort those by hand first -- nothing done.',
      v_clash;
  end if;

  ----------------------------------------------------------------
  -- Move the hours FIRST, then the assignments. Either order works inside
  -- one statement, but doing hours first means that if anything unexpected
  -- aborts, the assignments have not yet been detached from their hours.
  ----------------------------------------------------------------
  update public.time_entries set consultant_id = v_to where consultant_id = v_from;
  get diagnostics n_hours = row_count;

  update public.client_assignments set user_id = v_to where user_id = v_from;
  get diagnostics n_assign = row_count;

  if n_assign = 0 and n_hours = 0 then
    raise notice 'Nothing to move -- already merged.';
  else
    raise notice 'Moved % assignment row(s) and % time entry row(s).', n_assign, n_hours;
  end if;
end $$;

-- ---------------------------------------------------------------
-- Verify. Expect the Team Lead row to list all four engagements, and the
-- gmail row to show none.
-- ---------------------------------------------------------------
select
  au.email,
  pu.role::text                                       as eg_role,
  count(a.id)                                         as assignments,
  coalesce(string_agg(distinct c.name, ', ')
           filter (where a.is_team_lead), '-')        as leads,
  coalesce(string_agg(distinct c.name, ', ')
           filter (where not a.is_team_lead), '-')    as specialist_on
from auth.users au
join public.users pu on pu.id = au.id
left join public.client_assignments a on a.user_id = pu.id
left join public.clients c on c.id = a.client_id
where au.email in ('greggotcher@gmail.com', 'greg.gotcher@leadforcesolutions.com')
group by au.email, pu.role
order by au.email;
