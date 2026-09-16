-- fix_tl_login.sql   (9/16/26)
--
-- *** DO NOT SAVE THIS INTO THE eg-dashboard FOLDER. ***
-- That folder is a git repo that pushes to GitHub and deploys to Netlify.
-- Part 4 has a password in it. Run it from the Supabase SQL editor, then
-- close the tab. Nothing here belongs in version control.
--
-- Greg: "i cannot login, change the password, or delete,
-- greg.gotcher@leadforcesolutions.com. this is my TL login."
--
-- Three symptoms, and they are probably not three problems.
--
-- The tell is in the Supabase user panel: "Last signed in" is blank while
-- "Confirmed at" says 21 Aug, 2026 16:03. That account has never once been
-- signed into. An auth user created through the admin API without a password
-- looks exactly like this -- confirmed, valid, and impossible to sign in as,
-- because there is no password to be right about. That alone explains symptom
-- one, and it explains symptom two too: "change the password" from inside the
-- app requires signing in first.
--
-- "Send password recovery" not arriving is a separate thing: Supabase's
-- built-in SMTP is heavily rate-limited and on most projects will not deliver
-- to arbitrary addresses at all. That is the same missing-sending-domain
-- problem already on the October 1 list, wearing a different hat -- it is
-- fixed under Authentication -> Emails -> SMTP Settings, not in this file.
--
-- The delete failing is the third and it is unrelated to both: something has
-- a foreign key pointing at this auth user with no ON DELETE rule, so
-- Postgres refuses. Part 3 names it. (046_assignments_fk_set_null.sql shows
-- this has bitten before.)
--
-- BEFORE FIXING ANYTHING, run Parts 1 and 2. There are THREE Greg accounts in
-- that user list -- greg.gotcher@leadforcesolutions.com,
-- greg@leadforcesolutions.com, and greggotcher@gmail.com. If the Team Lead
-- profile is wired to a different one than you think, the answer is "log in
-- as the other account," not "repair this one." A never-signed-into account
-- is just as likely to be a stray duplicate as a broken login.
--
-- Parts 1-3 are read-only. Part 4 changes a password and is commented out.


-- ---------------------------------------------------------------
-- PART 1 -- The three auth accounts, side by side.
--
-- has_password is the column that matters. If it says 'no password set'
-- for the one you are trying to use, that is the whole story for symptoms
-- one and two.
-- ---------------------------------------------------------------
select
  u.email,
  u.id                                        as auth_uid,
  case
    when u.encrypted_password is null
      or u.encrypted_password = ''            then 'NO PASSWORD SET'
    else 'password set'
  end                                         as has_password,
  u.email_confirmed_at is not null            as confirmed,
  u.last_sign_in_at                           as last_signed_in,
  u.banned_until,
  u.deleted_at,
  u.created_at
from auth.users u
where u.email ilike '%gotcher%'
   or u.email ilike '%leadforcesolutions%'
order by u.created_at;


-- ---------------------------------------------------------------
-- PART 2 -- Which auth account each EG Dashboard profile is wired to,
-- and what each one is actually team lead of.
--
-- This is the question behind BOTH of today's puzzles. The engagement list
-- is driven by client_assignments.user_id, and that points at
-- public.users.id, which is supposed to equal the auth uid.
--
-- Read `engagements_as_team_lead`. Whichever row shows Clippard and
-- Extremis is your real Team Lead login -- sign in as THAT email.
-- A row with `profile_missing` means an auth account with no EG
-- Dashboard profile behind it: that one is a stray and is safe to remove
-- once Part 3 clears the way.
-- ---------------------------------------------------------------
select
  au.email,
  au.id                                         as auth_uid,
  -- users.role is an enum (user_role), so the fallback has to be cast to
  -- text before coalesce -- otherwise Postgres tries to read
  -- '(profile_missing)' as an enum value and throws 22P02.
  coalesce(pu.role::text, '(profile_missing)')  as eg_role,
  pu.full_name,
  count(a.id)                                   as assignment_rows,
  coalesce(
    string_agg(distinct c.name, ', ') filter (where a.is_team_lead),
    '(none)'
  )                                             as engagements_as_team_lead,
  coalesce(
    string_agg(distinct c.name, ', ') filter (where not a.is_team_lead),
    '(none)'
  )                                             as engagements_as_specialist
from auth.users au
left join public.users             pu on pu.id = au.id
left join public.client_assignments a on a.user_id = pu.id
left join public.clients            c on c.id = a.client_id
where au.email ilike '%gotcher%'
   or au.email ilike '%leadforcesolutions%'
group by au.email, au.id, pu.role, pu.full_name
order by au.email;


-- ---------------------------------------------------------------
-- PART 3 -- Why "Delete user" fails.
--
-- Every foreign key pointing at auth.users, and what each one does on
-- delete. Anything showing NO ACTION or RESTRICT with rows attached is
-- what Supabase is hitting. The usual culprit is public.users.id.
--
-- Do not "fix" these by dropping constraints. If the account turns out to
-- be a stray, delete its public.users row first and the auth delete will
-- then go through.
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
where con.confrelid = 'auth.users'::regclass
  and con.contype = 'f'
order by 3 desc, 1;


-- ---------------------------------------------------------------
-- PART 4 -- Set a password directly, WITHOUT needing email to work.
--
-- Only run this once Part 2 has confirmed this really is the account your
-- Team Lead profile is wired to. If it is not, sign in as the other one
-- instead and leave this account alone.
--
-- Uncomment, put a real password in place of both markers, run it, then
-- sign in normally. Change it from inside the app afterwards if you like.
-- Supabase keeps pgcrypto in the `extensions` schema; if your project has
-- it elsewhere, drop the `extensions.` prefix and re-run.
--
-- update auth.users
-- set encrypted_password = extensions.crypt('PUT-A-REAL-PASSWORD-HERE', extensions.gen_salt('bf')),
--     updated_at         = now(),
--     email_confirmed_at = coalesce(email_confirmed_at, now())
-- where email = 'greg.gotcher@leadforcesolutions.com';
--
-- Then confirm it took -- expect 'password set':
--
-- select email,
--        case when encrypted_password is null or encrypted_password = ''
--             then 'NO PASSWORD SET' else 'password set' end as has_password,
--        updated_at
-- from auth.users
-- where email = 'greg.gotcher@leadforcesolutions.com';
