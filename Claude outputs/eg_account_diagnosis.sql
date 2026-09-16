-- eg_account_diagnosis.sql   (9/16/26)
--
-- Read-only. Changes nothing. Select all, run once.
--
-- Everything comes back in ONE result grid. The earlier files were split
-- into parts, and the Supabase SQL editor only shows the grid for the LAST
-- statement in a run -- so Parts 1, 2 and A/B all executed and then had
-- their output overwritten by whatever came last. That is why only Part 3
-- and Part C ever made it to the screen.
--
-- Answers all of it at once:
--   * which Greg auth account can actually be signed in as
--   * which one your Team Lead profile is really wired to
--   * which one leads Clippard and Extremis
--   * what, if anything, is blocking the delete
--   * a plain-language verdict at the bottom
--
-- Read the VERDICT rows first. The rest is the evidence behind them.

drop table if exists eg_diag;
create temp table eg_diag (ord int, section text, finding text, detail text);

do $$
declare
  v_target uuid := '023f54b5-6cdf-4742-bd3a-c230c5207222';  -- greg.gotcher@leadforcesolutions.com
  r         record;
  n         bigint;
  blocked   bigint := 0;
  has_prof  boolean;
  can_login boolean;
  tl_email  text;
begin
  ------------------------------------------------------------------
  -- 1. The accounts
  ------------------------------------------------------------------
  for r in
    select
      au.email,
      au.id as uid,
      (au.encrypted_password is not null and au.encrypted_password <> '') as has_pw,
      au.last_sign_in_at,
      pu.role::text as eg_role,
      coalesce(
        (select string_agg(c.name, ', ' order by c.name)
           from public.client_assignments a
           join public.clients c on c.id = a.client_id
          where a.user_id = pu.id and a.is_team_lead),
        '-') as tl_of
    from auth.users au
    left join public.users pu on pu.id = au.id
    where au.email ilike '%gotcher%' or au.email ilike '%leadforcesolutions%'
    order by au.email
  loop
    insert into eg_diag values (
      1,
      'ACCOUNT',
      r.email,
      'sign-in: '   || case when r.has_pw then 'possible' else 'IMPOSSIBLE (no password set)' end
      || ' | last used: ' || coalesce(r.last_sign_in_at::date::text, 'NEVER')
      || ' | profile: '   || coalesce(r.eg_role, 'NONE (orphan auth account)')
      || ' | team lead of: ' || r.tl_of
    );
    if r.eg_role = 'team_lead' then tl_email := r.email; end if;
  end loop;

  select (encrypted_password is not null and encrypted_password <> '')
    into can_login from auth.users where id = v_target;
  has_prof := exists (select 1 from public.users where id = v_target);

  ------------------------------------------------------------------
  -- 2. What blocks deleting the target account.
  -- Deleting auth.users cascades into public.users; only children of
  -- public.users with NO ACTION / RESTRICT can hold that up.
  ------------------------------------------------------------------
  if has_prof then
    for r in
      select con.conrelid::regclass::text as child_table, att.attname as child_column
      from pg_constraint con
      join unnest(con.conkey) with ordinality as k(attnum, ord) on true
      join pg_attribute att on att.attrelid = con.conrelid and att.attnum = k.attnum
      where con.confrelid = 'public.users'::regclass
        and con.contype = 'f'
        and con.conrelid <> 'public.users'::regclass
        and con.confdeltype::text in ('a', 'r')
      order by 1
    loop
      execute format('select count(*) from %s where %I = $1', r.child_table, r.child_column)
        into n using v_target;
      if n > 0 then
        blocked := blocked + n;
        insert into eg_diag values (2, 'BLOCKS DELETE', r.child_table || '.' || r.child_column, n || ' row(s)');
      end if;
    end loop;
    if blocked = 0 then
      insert into eg_diag values (2, 'BLOCKS DELETE', '(nothing)', 'No NO ACTION / RESTRICT child has rows for this account.');
    end if;
  end if;

  ------------------------------------------------------------------
  -- 3. Verdict
  ------------------------------------------------------------------
  if not has_prof then
    insert into eg_diag values (9, 'VERDICT', '1. This account is an orphan',
      'greg.gotcher@leadforcesolutions.com has no EG Dashboard profile behind it. '
      || 'It is not your Team Lead login and never was.');
    insert into eg_diag values (9, 'VERDICT', '2. Sign in as this instead',
      coalesce(tl_email, 'see the ACCOUNT rows -- whichever one shows profile: team_lead'));
    insert into eg_diag values (9, 'VERDICT', '3. Safe to delete',
      'Nothing in the dashboard points at it, so deleting costs you no data. '
      || 'If Supabase still refuses, it is an auth-side issue, not a data one -- leaving it '
      || 'alone is harmless either way.');
  else
    insert into eg_diag values (9, 'VERDICT', '1. This account DOES hold a profile',
      'Deleting it cascades into public.users and blanks the Team Lead on its engagements '
      || '(client_assignments.user_id is SET NULL, per 046). Do not delete it.');
    insert into eg_diag values (9, 'VERDICT', '2. Why sign-in fails',
      case when can_login
        then 'A password IS set, so the failure is something else -- wrong password, or the '
             || 'account is banned. Check the banned_until column.'
        else 'No password was ever set on it. Nothing you type can be right. Set one with '
             || 'Part 4 of fix_tl_login.sql, which bypasses email entirely.' end);
    insert into eg_diag values (9, 'VERDICT', '3. Why delete fails',
      case when blocked > 0
        then blocked || ' row(s) in the tables listed above have no delete rule. '
             || 'That is what Postgres is refusing on.'
        else 'Nothing is blocking it at the database level -- but you should not be deleting '
             || 'this account anyway. See verdict 1.' end);
  end if;
end $$;

select section, finding, detail
from eg_diag
order by ord, finding;
