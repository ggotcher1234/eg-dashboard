-- verify_tl_engagements.sql   (9/16/26)
--
-- Read-only. One row per engagement per specialty, so nothing is truncated.
--
-- The merge reported 6 assignment rows across 4 engagements, which is what it
-- looks like when you hold a Team Lead row AND one or more specialist rows on
-- the same engagement -- client_assignments is one row per specialty, not one
-- per person per engagement. This lists them out so you can confirm that is
-- all it is.
--
-- Expect: every engagement you work on, each with the specialty you hold on
-- it, all under greg.gotcher@leadforcesolutions.com, and nothing under the
-- gmail account.

select
  c.name                                   as engagement,
  p.code                                   as program,
  a.specialty_type                         as specialty,
  case when a.is_team_lead then 'TEAM LEAD' else 'specialist' end as capacity,
  a.hours_allotted                         as budget_hours,
  au.email                                 as under_login
from public.client_assignments a
join public.users pu on pu.id = a.user_id
join auth.users  au on au.id = pu.id
join public.clients c on c.id = a.client_id
left join public.econ_dev_companies p on p.id = c.econ_dev_company_id
where au.email in ('greggotcher@gmail.com', 'greg.gotcher@leadforcesolutions.com')
order by c.name, a.is_team_lead desc, a.specialty_type;
