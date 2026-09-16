-- set_tl_password.sql   (9/16/26)
--
-- *** DO NOT SAVE THIS INTO THE eg-dashboard FOLDER. ***
-- That folder is a git repo that pushes to GitHub and deploys to Netlify.
-- There is a password in it. Run it, then close the tab.
--
-- WHAT THE DIAGNOSIS ACTUALLY FOUND
--
--   greg.gotcher@leadforcesolutions.com   password set | LAST USED: NEVER | team_lead  | leads Clippard + Extremis
--   greg@leadforcesolutions.com           password set | last used 9/11   | super_admin
--   greggotcher@gmail.com                 password set | last used 9/16   | consultant | leads JCS
--
-- So I was wrong twice, and both corrections matter:
--
-- 1. It is NOT an orphan. greg.gotcher@leadforcesolutions.com holds your real
--    Team Lead profile and is the Team Lead on Clippard and Extremis.
--    DO NOT DELETE IT. Deleting cascades into public.users and, because
--    client_assignments.user_id is SET NULL (046), it would quietly blank the
--    Team Lead on both engagements rather than throwing an error.
--
-- 2. A password IS set on it. My "no password" theory is dead. But it has
--    never been signed into -- which fits an account created by
--    admin-create-team-member with a generated password that nobody ever
--    saw, and whose set-your-password email never arrived, because Supabase's
--    built-in SMTP does not reliably deliver. You are not typing it wrong.
--    You were never given it.
--
-- That also explains this morning's other puzzle. You were signed in as
-- greggotcher@gmail.com, the consultant account, which is on JCS and JLR --
-- so those are the two you saw. Clippard and Extremis live on the Team Lead
-- account you cannot get into. One cause, two symptoms.
--
-- This file sets a password you choose, without needing email to work.
-- It touches one column on one row in auth.users. It does not go near
-- public.users, so the trg_users_super_admin_guard trigger is not involved.

do $$
declare
  v_email    text := 'greg.gotcher@leadforcesolutions.com';
  v_password text := 'PUT-YOUR-PASSWORD-HERE';   -- <<< CHANGE THIS BEFORE RUNNING
  v_schema   text;
  v_rows     int;
begin
  if v_password = 'PUT-YOUR-PASSWORD-HERE' then
    raise exception 'Edit v_password first -- line 41. Nothing was changed.';
  end if;
  if length(v_password) < 8 then
    raise exception 'Supabase rejects sign-in passwords under 8 characters. Nothing was changed.';
  end if;

  -- pgcrypto lives in `extensions` on Supabase, `public` elsewhere. Find it
  -- rather than making you guess and re-run.
  select n.nspname into v_schema
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where p.proname = 'crypt'
  limit 1;

  if v_schema is null then
    raise exception 'pgcrypto is not installed -- run: create extension pgcrypto with schema extensions;';
  end if;

  execute format(
    'update auth.users
        set encrypted_password = %I.crypt($1, %I.gen_salt(''bf'')),
            updated_at         = now(),
            email_confirmed_at = coalesce(email_confirmed_at, now()),
            banned_until       = null
      where email = $2',
    v_schema, v_schema
  ) using v_password, v_email;

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    raise exception 'No auth user matched %. Nothing was changed.', v_email;
  end if;

  raise notice 'Password set for % (pgcrypto found in %).', v_email, v_schema;
end $$;

-- Confirms it took. Sign in with the password you just set.
select
  email,
  case when encrypted_password is null or encrypted_password = ''
       then 'NO PASSWORD' else 'password set' end as has_password,
  email_confirmed_at is not null                  as confirmed,
  banned_until,
  last_sign_in_at                                 as last_signed_in,
  updated_at
from auth.users
where email = 'greg.gotcher@leadforcesolutions.com';
