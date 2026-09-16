-- diagnose_specialist_visibility.sql   (9/16/26)
--
-- NOT a migration. Changes nothing. Read-only. Safe to run any time.
--
-- Greg: "i am missing two accounts that i am the team lead for. Extremis and
-- Clippard. why are they not showing up when i'm logged in as a specialist."
--
-- index.html loads the list with a bare `select * from clients` -- there is no
-- client-side filter on that query at all, so whatever the list shows is
-- exactly what RLS handed back. Two engagements missing means the database
-- withheld them from that login.
--
-- The hypothesis this checks: visibility follows CLIENT_ASSIGNMENTS, not who
-- the Team Lead is. Greg holds three separate logins with the same name
-- (Super Admin, Team Lead, Specialist -- see the comment in index.html around
-- showSignedInEmail()). If Clippard and Extremis carry an assignment row for
-- the TEAM LEAD account and none for the SPECIALIST account, then the
-- Specialist login is genuinely not on those two teams and the list is right.
--
-- Supporting evidence for that before you even run this: JLR Environmental is
-- Travin Shelton's engagement, not Greg's, and it DOES show up. So the list is
-- not "engagements you lead" -- it is "engagements you are on."
--
-- Run all three parts. Part 3 is the one that answers the question.

-- ---------------------------------------------------------------
-- PART 1 -- The accounts. Expect three rows, one per login.
-- If you see fewer, the missing ones are under a different name spelling.
-- ---------------------------------------------------------------
select
  u.id,
  u.full_name,
  u.email,
  u.role,
  case u.role
    when 'super_admin' then 'the Admin login'
    when 'team_lead'   then 'the Team Lead login'
    when 'consultant'  then 'the Specialist login'   -- UI label is "Specialist"
    else u.role
  end as which_login
from users u
where u.full_name ilike '%gotcher%'
   or u.email     ilike '%gotcher%'
order by u.role, u.email;


-- ---------------------------------------------------------------
-- PART 2 -- Status check, so a wrong project_status is ruled out as the
-- cause. The list Greg is looking at shows In Progress only.
-- Expect all four engagements to say 'in_progress'.
-- ---------------------------------------------------------------
select
  c.name           as engagement,
  c.project_status,
  p.code           as program,
  c.first_in_progress_at::date as in_progress_since
from clients c
left join econ_dev_companies p on p.id = c.econ_dev_company_id
where c.name ilike any (array['%clippard%', '%extremis%', '%jcs%', '%jlr%'])
order by c.name;


-- ---------------------------------------------------------------
-- PART 3 -- The answer. For each of the four engagements, which of Greg's
-- logins actually has an assignment row on it.
--
-- Read the last two columns. The prediction is:
--   JCS, JLR              -> on_specialist_login = yes   (these show up)
--   Clippard, Extremis    -> on_specialist_login = no    (these do not)
-- If that is what comes back, nothing is broken -- the Specialist login is
-- not a member of those two teams, and the fix is a decision, not a patch.
-- ---------------------------------------------------------------
with greg as (
  select id, role from users
  where full_name ilike '%gotcher%' or email ilike '%gotcher%'
)
select
  c.name as engagement,
  c.project_status,
  coalesce(
    string_agg(
      distinct g.role || ' (' || a.specialty_type || case when a.is_team_lead then ', TL' else '' end || ')',
      ', ' order by g.role || ' (' || a.specialty_type || case when a.is_team_lead then ', TL' else '' end || ')'
    ),
    'none of Greg''s logins'
  ) as greg_is_on_this_as,
  case when bool_or(g.role = 'consultant') then 'yes' else 'NO' end as on_specialist_login,
  case when bool_or(g.role = 'team_lead')  then 'yes' else 'no'  end as on_team_lead_login
from clients c
left join client_assignments a on a.client_id = c.id
left join greg g on g.id = a.user_id
where c.name ilike any (array['%clippard%', '%extremis%', '%jcs%', '%jlr%'])
group by c.id, c.name, c.project_status
order by c.name;
