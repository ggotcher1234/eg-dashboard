-- rls_visibility_test.sql   (9/16/26)
--
-- READ-ONLY. Changes no data. Select all, run once, read the grid.
--
-- THE QUESTION
-- "An EG Team Lead can be a Team Lead on some accounts and a specialist on
-- others ... they need to see all their accounts."
--
-- The merge put all of Greg's work on one login. But whether that login can
-- SEE all of it is decided by the row-level security policy on `clients`, and
-- that policy predates migration 017 so it is not in the repo.
--
-- Rather than print the policy and make you interpret SQL, this asks the
-- database directly: it takes on each account's identity in turn, runs the
-- exact query the Engagements page runs, and reports what comes back. Whatever
-- this says is what you will see when you sign in.
--
-- HOW, AND WHY IT IS SAFE
-- The SQL editor connects as `postgres`, which bypasses RLS entirely -- so
-- simply querying here would prove nothing. Two transaction-local settings fix
-- that: the JWT claims make auth.uid() return the account being tested, and
-- switching to the `authenticated` role makes RLS actually apply. Both use
-- set_config(..., true), which reverts when the statement ends, including on
-- error. Nothing is left changed. No policy is disabled at any point -- the
-- whole point is to let the policy do its job and watch what it does.

drop table if exists rls_probe;
create temp table rls_probe (
  ord int, login text, eg_role text,
  assigned_to int, can_see int, verdict text, missing text
);

do $$
declare
  v_orig text := coalesce(current_setting('role', true), 'none');
  r record;
  v_seen    text[];
  v_assigned text[];
  v_missing text;
  i int := 0;
begin
  for r in
    select au.email, au.id as uid, pu.role::text as eg_role
    from auth.users au
    join public.users pu on pu.id = au.id
    where au.email in (
      'greg.gotcher@leadforcesolutions.com',
      'greggotcher@gmail.com',
      'greg@leadforcesolutions.com'
    )
    order by au.email
  loop
    i := i + 1;

    -- what this account is actually assigned to (read as postgres)
    select array_agg(distinct c.name order by c.name) into v_assigned
    from public.client_assignments a
    join public.clients c on c.id = a.client_id
    where a.user_id = r.uid;
    v_assigned := coalesce(v_assigned, '{}');

    -- become that account, with RLS switched on
    perform set_config('request.jwt.claims',
      json_build_object('sub', r.uid::text, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', r.uid::text, true);
    perform set_config('role', 'authenticated', true);

    -- the query index.html runs, under that identity
    begin
      select array_agg(distinct c.name order by c.name) into v_seen
      from public.clients c;
    exception when others then
      v_seen := null;
    end;
    v_seen := coalesce(v_seen, '{}');

    -- back to postgres before writing anything down
    perform set_config('role', v_orig, true);

    select string_agg(x, ', ') into v_missing
    from unnest(v_assigned) x
    where not (x = any (v_seen));

    insert into rls_probe values (
      i, r.email, r.eg_role,
      array_length(v_assigned, 1),
      array_length(v_seen, 1),
      case
        when v_missing is not null
          then 'POLICY PROBLEM -- assigned but cannot see'
        when array_length(v_assigned, 1) is null
          then 'no assignments (nothing to test)'
        else 'OK -- sees everything it is assigned to'
      end,
      coalesce(v_missing, '-')
    );
  end loop;

  perform set_config('role', v_orig, true);
end $$;

select
  login,
  eg_role,
  coalesce(assigned_to, 0) as engagements_assigned,
  coalesce(can_see, 0)     as engagements_visible,
  verdict,
  missing                  as cannot_see
from rls_probe
order by ord;
