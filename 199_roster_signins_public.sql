-- 199: who has signed in, as an open page.
--
-- Greg (22/11/26), after the Roster Sign-ins artifact failed to load: "i
-- have no need to secure this page in any way. it can easily be an open web
-- page. it's just a list of who has logged in. no security needed."
--
-- The artifact reached the database through the VIEWER'S own Supabase
-- connector, so it worked only for a signed-in Greg whose permission grant
-- had not lapsed -- and when it lapsed it failed with a raw protocol error.
-- (The same refusal hit this session's tools the same afternoon, which is
-- how we know it was the connector and not the page.)
--
-- This replaces that route with the one the client dashboard and the
-- Discovery share page already use: a security-definer function granted to
-- anon, reading exactly what it is allowed to read.
--
-- WHAT IT RETURNS, AND WHAT IT DOES NOT
-- Name, role, whether a password email has gone out, and the last sign-in.
-- Deliberately NOT the email address: it adds nothing to "who has logged
-- in", and thirty staff addresses on an open page is a mailing list for
-- whoever finds it.
--
-- Archived members are left off: their sign-in is revoked, so "never signed
-- in" would read as a chore rather than a fact.
create or replace function public.get_roster_signins_public()
returns table (
  full_name text,
  role text,
  invited_at timestamptz,
  last_sign_in_at timestamptz
)
language plpgsql
security definer
set search_path to 'public'
as $fn$
begin
  -- auth.users is not reachable through PostgREST by anybody, which is why
  -- this needs a function rather than a view with a grant on it.
  set local row_security = off;

  return query
    select u.full_name,
           u.role::text,
           -- The welcome/password email. Supabase records it as a recovery
           -- send, which is what the old artifact's "Invited" state read.
           au.recovery_sent_at,
           au.last_sign_in_at
    from users u
    join auth.users au on au.id = u.id
    where u.archived_at is null
    order by au.last_sign_in_at desc nulls last, u.full_name;
end;
$fn$;

grant execute on function public.get_roster_signins_public() to anon;
grant execute on function public.get_roster_signins_public() to authenticated;
