-- 145_role_view_overrides.sql (10/6/26)   [APPLIED in three parts: a, b, c]
--
-- Greg: "i need to have one login - Admin, but i need to change my view to TL
-- or Specialist to see what they see."
--
-- A UI-only switch would not have done it. 69 RLS policies call
-- is_super_admin(), so hiding buttons would leave the database still
-- answering as Admin: the whole engagement list would still come back, and a
-- save a Specialist would be refused would still succeed. The switch has to
-- be server-side to be worth anything, and the cheapest honest place is
-- is_super_admin() itself -- all 69 policies then inherit it.
--
-- Applied in three statements because DROP hangs on the MCP connection (so
-- nothing is dropped; existence is checked against the catalog), and because
-- a single call timed out at 180s.
--
-- Verified live, as the authenticated role so RLS applied:
--   baseline        super_admin=t  effective=super_admin  engagements=6  TL(Extremis)=t
--   as Team Lead    super_admin=f  effective=team_lead    engagements=5  TL(Extremis)=t
--   as Specialist   super_admin=f  effective=consultant   engagements=5  TL(Extremis)=f
--   after clearing  super_admin=t  effective=super_admin  engagements=6
--   a real consultant writing {effective_role: super_admin} for themselves:
--                   super_admin=f  effective=consultant   engagements=1

----------------------------------------------------------------- 145a: table
-- YOU CANNOT LOCK YOURSELF OUT. These policies key on user_id = auth.uid()
-- and nothing else -- no role test anywhere -- so clearing your own override
-- never depends on the privilege the override just removed. expires_at is the
-- second belt: a forgotten override heals itself.
create table if not exists role_view_overrides (
  user_id        uuid primary key references users(id) on delete cascade,
  effective_role user_role   not null,
  started_at     timestamptz not null default now(),
  expires_at     timestamptz not null default now() + interval '2 hours'
);

alter table role_view_overrides enable row level security;

do $$
declare t oid := to_regclass('public.role_view_overrides');
begin
  if not exists (select 1 from pg_policy where polrelid=t and polname='rvo_select') then
    create policy rvo_select on role_view_overrides for select using (user_id = auth.uid());
  end if;
  if not exists (select 1 from pg_policy where polrelid=t and polname='rvo_insert') then
    create policy rvo_insert on role_view_overrides for insert with check (user_id = auth.uid());
  end if;
  if not exists (select 1 from pg_policy where polrelid=t and polname='rvo_update') then
    create policy rvo_update on role_view_overrides for update using (user_id = auth.uid()) with check (user_id = auth.uid());
  end if;
  if not exists (select 1 from pg_policy where polrelid=t and polname='rvo_delete') then
    create policy rvo_delete on role_view_overrides for delete using (user_id = auth.uid());
  end if;
end $$;

------------------------------------------------------------- 145b: functions
-- AN OVERRIDE CAN ONLY REMOVE PRIVILEGE, NEVER GRANT IT. is_super_admin()
-- still requires the REAL users.role to be super_admin and merely ANDs the
-- override on top.
create or replace function active_role_override(p_user uuid)
returns user_role
language sql stable security definer set search_path = public as $$
  select o.effective_role from role_view_overrides o
   where o.user_id = p_user and o.expires_at > now() limit 1;
$$;

create or replace function is_super_admin()
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from users u where u.id = auth.uid() and u.role = 'super_admin')
     and coalesce(active_role_override(auth.uid()), 'super_admin'::user_role) = 'super_admin';
$$;

-- Viewing as a Specialist has to drop Team Lead too. Greg leads all four of
-- his engagements, so without this he would still be able to edit every one
-- of them and would never actually see what a Specialist sees.
create or replace function is_team_lead_of_client(target_client uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(active_role_override(auth.uid()), 'team_lead'::user_role) <> 'consultant'
     and exists (select 1 from client_assignments ca
                  where ca.client_id = target_client and ca.user_id = auth.uid() and ca.is_team_lead);
$$;

----------------------------------------------------------------- 145c: clamp
-- Caught while testing 145b: a real Specialist who wrote
-- {effective_role: super_admin} for themselves gained no actual privilege --
-- is_super_admin() stayed false, they still saw only their own engagement --
-- but my_effective_role() answered 'super_admin', so the PAGE would have
-- dressed itself as Admin for them and every button would fail on click.
-- Not a privilege hole; a lying interface, which is its own bug.
-- An override may only ever point DOWN: effective = min(real, override).
create or replace function role_rank(r user_role)
returns int language sql immutable as $$
  select case r when 'super_admin' then 3 when 'team_lead' then 2 else 1 end;
$$;

create or replace function my_effective_role()
returns text
language sql stable security definer set search_path = public as $$
  with me as (select u.role as real_role from users u where u.id = auth.uid()),
       ov as (select active_role_override(auth.uid()) as want)
  select case
           when (select want from ov) is null then (select real_role::text from me)
           when role_rank((select want from ov)) < role_rank((select real_role from me))
             then (select want::text from ov)
           else (select real_role::text from me)
         end;
$$;
