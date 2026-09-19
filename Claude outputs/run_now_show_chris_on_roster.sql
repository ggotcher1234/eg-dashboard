-- run_now_show_chris_on_roster.sql   (9/19/26)
--
-- Greg: "chris would like to be viewable on the roster. let's show his contact
-- info and Admin role."
--
-- *** Run this in the Supabase SQL editor. Don't save it into the
-- *** eg-dashboard folder -- that folder is a git repo that pushes to GitHub
-- *** and deploys to Netlify.
--
-- What I found on the live roster (with "Show hidden" ticked): there are TWO
-- Chris Gibbons accounts, both hidden, and both already Admin --
--
--   4efbea10-5fe1-4101-b188-5ec2392e1360   cgibbons@economicgardening.org
--       phone (303) 670-3599, no company, no address
--   (the other one)                        christiangibbons47@gmail.com
--       phone (303) 670-3599, company NCEG, POB 2583 Evergreen CO 80437
--
-- You picked the work address as the one to show, so this un-hides that
-- account and copies the company and mailing address across from the personal
-- one, which stays hidden. Role is untouched -- it is already super_admin,
-- which the roster renders as "Admin".
--
-- I tried to do this through the app itself, but Chrome is signed in as your
-- Team Lead account and the save was refused ("you don't have permission to
-- edit this profile") -- correctly, since only an Admin can edit someone
-- else's profile. Nothing was changed. Running this does it regardless of
-- which login you happen to be in; the alternative is to sign in as your
-- Admin account, tick "Show hidden" on the Roster, open Chris, untick
-- "Hide from Roster", and fill in the two fields by hand.
--
-- Guarded: it refuses unless that id is Chris, an Admin, and currently hidden.
-- Safe to re-run -- the second run reports he is already visible and stops.

do $$
declare
  v_chris uuid := '4efbea10-5fe1-4101-b188-5ec2392e1360';
  r       record;
  n       int;
begin
  select id, full_name, email, role::text as role, hidden_from_roster, company_name, address
    into r
  from users
  where id = v_chris;

  if not found then
    raise exception 'No user with that id. Nothing was changed.';
  end if;

  if lower(r.email) <> 'cgibbons@economicgardening.org' or r.full_name not ilike '%gibbons%' then
    raise exception
      'Stopping -- that id is % <%>, not the Chris Gibbons work account this file expects. Nothing was changed.',
      r.full_name, r.email;
  end if;

  if r.role <> 'super_admin' then
    raise exception
      'Stopping -- that account is % rather than super_admin, so it would not show as Admin. Nothing was changed.',
      r.role;
  end if;

  if r.hidden_from_roster = false then
    raise notice 'Already visible on the Roster. Nothing to do.';
    return;
  end if;

  update users
     set hidden_from_roster = false,
         -- coalesce: only fills a blank, never overwrites something he has set
         company_name = coalesce(nullif(trim(coalesce(company_name, '')), ''), 'NCEG'),
         address      = coalesce(nullif(trim(coalesce(address, '')), ''), 'POB 2583, Evergreen CO 80437')
   where id = v_chris;
  get diagnostics n = row_count;

  if n <> 1 then
    raise exception 'Expected to update exactly 1 row, updated %. Rolled back.', n;
  end if;

  raise notice 'Chris Gibbons (%) is now on the Roster as Admin.', r.email;
end $$;

-- Expect: the work account visible, the personal one still hidden.
select
  full_name,
  email,
  role::text            as eg_role,
  hidden_from_roster,
  coalesce(company_name, '(none)') as company,
  coalesce(address, '(none)')      as address,
  coalesce(phone, '(none)')        as phone
from users
where full_name ilike '%gibbons%'
order by hidden_from_roster, email;
