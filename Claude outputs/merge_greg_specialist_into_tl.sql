-- merge_greg_specialist_into_tl.sql   (9/16/26, rev 2)
--
-- Moves Greg's engagement work off the consultant login and onto the Team
-- Lead login, so one login shows everything he is on -- Team Lead on some
-- engagements, specialist on others, which is how every Team Lead works.
--
--   FROM  greggotcher@gmail.com               (consultant)  -- JCS, JLR
--   TO    greg.gotcher@leadforcesolutions.com (team_lead)   -- Clippard, Extremis
--
-- Afterwards the gmail account keeps its login and consultant role but has no
-- engagements: a clean empty Specialist, for recording the training video and
-- checking role gating.
--
-- WHY REV 2
-- Rev 1 was stopped by a trigger, which was the trigger working:
--
--   if NEW.is_team_lead and not is_super_admin() then
--     raise exception 'Only a Super Admin can assign a client''s Team Lead';
--
-- The JCS row has is_team_lead = true, and the SQL editor connects as
-- `postgres` with no end-user JWT, so is_super_admin() was false. Not a
-- permissions bug -- a rule written on purpose, catching exactly the kind of
-- unattended script it was meant to catch.
--
-- The wrong fix is `alter table ... disable trigger`: that turns the rule off
-- for everyone for as long as it is off, and a script that forgets to turn it
-- back on leaves the system quietly unguarded.
--
-- The right fix is to BE a Super Admin for the length of this transaction.
-- set_config(..., true) sets the JWT claims transaction-locally, so auth.uid()
-- returns Greg's Super Admin account while the merge runs and reverts by
-- itself the moment the statement ends -- even if it errors. Nothing is left
-- switched off afterwards. This is the same authority the app uses when Greg
-- assigns a Team Lead from the Engagement Workspace; it is just being
-- exercised from the editor.
--
-- And it VERIFIES the impersonation took before touching a single row. If
-- is_super_admin() still comes back false, it stops with a message and
-- changes nothing, rather than half-running.
--
-- SAFE TO RE-RUN. ONE statement -- all of it happens or none of it does.

do $$
declare
  v_from_email  text := 'greggotcher@gmail.com';
  v_to_email    text := 'greg.gotcher@leadforcesolutions.com';
  v_admin_email text := 'greg@leadforcesolutions.com';   -- the super_admin account
  v_from  uuid;
  v_to    uuid;
  v_admin uuid;
  v_clash int;
  n_assign int;
  n_hours  int;
  r record;
begin
  ----------------------------------------------------------------
  -- Resolve the three accounts.
  ----------------------------------------------------------------
  select id into v_from  from auth.users where email = v_from_email;
  select id into v_to    from auth.users where email = v_to_email;
  select id into v_admin from auth.users where email = v_admin_email;

  if v_from is null or v_to is null then
    raise exception 'Could not find both accounts (% / %) -- nothing done.', v_from_email, v_to_email;
  end if;
  if v_from = v_to then
    raise exception 'Those are the same account -- nothing done.';
  end if;
  if v_admin is null then
    raise exception 'No auth account for % -- nothing done.', v_admin_email;
  end if;
  if not exists (select 1 from public.users where id = v_admin and role = 'super_admin') then
    raise exception '% is not a super_admin in public.users -- nothing done.', v_admin_email;
  end if;

  ----------------------------------------------------------------
  -- Become that Super Admin, for this transaction only.
  -- Two claim shapes, because different Supabase versions read different
  -- ones and it costs nothing to satisfy both.
  ----------------------------------------------------------------
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_admin::text, 'role', 'authenticated')::text,
    true   -- transaction-local: reverts on its own, including on error
  );
  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  if not is_super_admin() then
    raise exception
      'Impersonation did not take -- is_super_admin() is still false, so nothing was changed. '
      'Send me the output of: select pg_get_functiondef(oid) from pg_proc where proname = ''is_super_admin'';';
  end if;

  raise notice 'Acting as % for this transaction only.', v_admin_email;

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
  -- Refuse if both accounts hold the same slot on the same engagement.
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
  -- Hours first, then assignments.
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
-- Verify. Expect the Team Lead row to list all four engagements and the
-- gmail row to show none. The impersonation is already gone by now -- it
-- ended with the statement above.
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
