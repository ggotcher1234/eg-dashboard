-- 172_client_team_standing_members.sql
--
-- Greg (10/20/26), looking at Chestnut Ridge Workshop's new dashboard:
-- "all dashboards should always include Chris Gibbons on the Economic
-- Gardening Team" ... "use the order TL, Specialists, Chris Gibbons".
--
-- Two things here. A roster flag for anyone whose place on the team is the
-- programme rather than the engagement -- no client_assignment, no hours
-- logged, but the client should see them -- and a reordering of the team so
-- the Team Lead is first instead of sixth.
--
-- A flag rather than Chris's name in the page, for the same reason the CC
-- line became one in 128: the first time it is two people, a hardcoded name
-- has to be found and edited. The Roster's "Show on every client dashboard"
-- tickbox is what sets it.
--
-- The order was `ca.specialty_type, ca.slot_number` -- alphabetical, which
-- put team_lead sixth of seven. Sorting on (specialty_type <> 'team_lead')
-- first lifts the Team Lead out and leaves everyone else as they were.
--
-- Both branches of the view are covered. The finalized branch reads a
-- snapshot frozen at close, which is the record of who did the work; a
-- standing name is appended to it rather than written into it, and skipped
-- if the snapshot already holds that address.

alter table users add column if not exists show_on_client_team boolean not null default false;

comment on column users.show_on_client_team is
  'Greg (10/20/26): "all dashboards should always include Chris Gibbons on the Economic Gardening Team." Someone whose place on the team is the programme rather than this engagement -- they hold no client_assignment and log no hours, but the client should see them. Appended after the assigned team on the public dashboard.';

do $$
begin
  -- The guard trigger reads auth.uid(), which is null in the SQL editor, so
  -- it refuses an update it would wave through in the app.
  alter table users disable trigger trg_users_super_admin_guard;

  update users
     set show_on_client_team = true
   where email = 'cgibbons@economicgardening.org'
     and archived_at is null;

  -- Client-facing on every dashboard now, so it should read like a phone
  -- number. The same person's archived login already had it this way.
  update users set phone = '303.670.3599'
   where email = 'cgibbons@economicgardening.org' and phone = '13036703599';

  alter table users enable trigger trg_users_super_admin_guard;
end $$;

-- get_client_public_view is ~180 lines and only three fragments change, so
-- it is rewritten from its own live definition rather than retyped. Each
-- replace is checked, so a definition that has moved on raises instead of
-- silently applying two of the three.
do $$
declare
  v_def text := pg_get_functiondef('public.get_client_public_view(text)'::regprocedure);
  v_new text;
  v_rows text :=
    '          select jsonb_agg(jsonb_build_object(''name'', fu.full_name, ''specialty'', fu.title, ''email'', fu.email, ''phone'', fu.phone) order by fu.full_name)' || chr(10) ||
    '          from users fu' || chr(10) ||
    '          where fu.show_on_client_team' || chr(10) ||
    '            and fu.archived_at is null' || chr(10);
begin
  -- 1. Team Lead first, then the rest alphabetically as before.
  v_new := replace(v_def,
    'order by ca.specialty_type, ca.slot_number)',
    'order by (ca.specialty_type <> ''team_lead''), ca.specialty_type, ca.slot_number)');
  if v_new = v_def then raise exception 'order-by clause not found'; end if;

  -- 2. Flagged roster people after the engagement team and the Program
  --    contacts, on the live branch.
  v_def := v_new;
  v_new := replace(v_def,
    '          where ctpc.client_id = v_client.id and pc.active' || chr(10) || '        ), ''[]''::jsonb);',
    '          where ctpc.client_id = v_client.id and pc.active' || chr(10) ||
    '        ), ''[]''::jsonb)' || chr(10) ||
    '        ||' || chr(10) ||
    '        coalesce((' || chr(10) || v_rows ||
    '            and not exists (' || chr(10) ||
    '              select 1 from client_assignments ca2' || chr(10) ||
    '               where ca2.client_id = v_client.id and ca2.user_id = fu.id' || chr(10) ||
    '            )' || chr(10) ||
    '        ), ''[]''::jsonb);');
  if v_new = v_def then raise exception 'partner-contact tail not found'; end if;

  -- 3. Same on the finalized branch, whose team is a snapshot.
  v_def := v_new;
  v_new := replace(v_def,
    '        s.next_steps, s.team' || chr(10) || '      from engagement_snapshots s',
    '        s.next_steps,' || chr(10) ||
    '        s.team || coalesce((' || chr(10) || v_rows ||
    '            and not exists (' || chr(10) ||
    '              select 1 from jsonb_array_elements(s.team) t' || chr(10) ||
    '               where lower(t->>''email'') = lower(fu.email)' || chr(10) ||
    '            )' || chr(10) ||
    '        ), ''[]''::jsonb)' || chr(10) ||
    '      from engagement_snapshots s');
  if v_new = v_def then raise exception 'finalized branch not found'; end if;

  execute v_new;
end $$;
