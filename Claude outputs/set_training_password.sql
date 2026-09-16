-- set_training_password.sql   (9/16/26)
--
-- *** DO NOT SAVE THIS INTO THE eg-dashboard FOLDER. ***
-- It has a password in it and that folder pushes to GitHub.
--
-- Sets the password for the shared training login (training@economicgardening.org,
-- "Research Specialist") so it can be signed into without the invite email,
-- which will not deliver until the sending domain is set up.
--
-- Same approach that fixed the Team Lead login: it writes one column on one
-- row in auth.users, finds pgcrypto's schema itself, and refuses to run while
-- the placeholder is still in place.
--
-- IT ALSO CHECKS THE ACCOUNT IS PROPERLY FORMED FIRST. admin-create-team-member
-- makes two things -- an auth.users row and a public.users profile -- and if it
-- errored partway through (for example while trying to send the invite) you can
-- end up with one and not the other. An account with a profile but no auth row
-- cannot be signed into at all; one with an auth row but no profile signs in
-- and then bounces straight back out with "no matching staff profile". Both
-- look like "the password doesn't work", so this rules them out before
-- touching anything.
--
-- Pick a password you are willing to give to every trainee -- this is a shared
-- practice login, not a personal one. Something like a passphrase everyone can
-- type. Nothing sensitive lives behind it: the sandbox engagement is fake.

do $$
declare
  v_email    text := 'training@economicgardening.org';
  v_password text := 'PUT-A-SHARED-PASSWORD-HERE';   -- <<< CHANGE THIS
  v_schema   text;
  v_uid      uuid;
  v_role     text;
  v_rows     int;
begin
  if v_password = 'PUT-A-SHARED-PASSWORD-HERE' then
    raise exception 'Edit v_password first. Nothing was changed.';
  end if;
  if length(v_password) < 8 then
    raise exception 'Supabase rejects passwords under 8 characters. Nothing was changed.';
  end if;

  select id into v_uid from auth.users where lower(email) = lower(v_email);
  select role::text into v_role from public.users where id = v_uid;

  if v_uid is null then
    raise exception
      'No auth account for %. The roster record may exist without a login behind it -- '
      'delete the roster member and re-add it, and tell me what error appears.', v_email;
  end if;
  if v_role is null then
    raise exception
      'Auth account exists for % but it has no EG Dashboard profile. It would sign in and '
      'immediately bounce out. Nothing changed -- send me this message.', v_email;
  end if;
  if v_role <> 'consultant' then
    raise warning 'Heads up: this account''s role is %, not consultant (Specialist).', v_role;
  end if;

  select n.nspname into v_schema
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where p.proname = 'crypt' limit 1;

  if v_schema is null then
    raise exception 'pgcrypto is not installed -- run: create extension pgcrypto with schema extensions;';
  end if;

  execute format(
    'update auth.users
        set encrypted_password = %I.crypt($1, %I.gen_salt(''bf'')),
            updated_at         = now(),
            email_confirmed_at = coalesce(email_confirmed_at, now()),
            banned_until       = null
      where id = $2',
    v_schema, v_schema
  ) using v_password, v_uid;

  get diagnostics v_rows = row_count;
  raise notice 'Password set for % (role %, % row updated).', v_email, v_role, v_rows;
end $$;

-- Confirm. Expect: password set, confirmed true, role consultant.
select
  au.email,
  case when au.encrypted_password is null or au.encrypted_password = ''
       then 'NO PASSWORD' else 'password set' end as has_password,
  au.email_confirmed_at is not null               as confirmed,
  au.banned_until,
  au.last_sign_in_at                              as last_signed_in,
  pu.full_name,
  pu.role::text                                   as eg_role
from auth.users au
left join public.users pu on pu.id = au.id
where lower(au.email) = 'training@economicgardening.org';
