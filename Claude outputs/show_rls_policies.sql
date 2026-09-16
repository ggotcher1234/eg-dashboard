-- show_rls_policies.sql   (9/16/26)
--
-- Read-only. Select all, run once. One grid.
--
-- Greg: "An EG Team Lead can be a Team Lead on some accounts and a specialist
-- on others ... my team lead login should see my TL accounts and my specialist
-- accounts. same as all TL's."
--
-- Agreed. Two different things could be preventing that, and they need
-- opposite fixes, so it is worth knowing which before touching anything.
--
--   DATA problem -- your JCS and JLR assignment rows sit on the
--   greggotcher@gmail.com account, not on the Team Lead account. Moving them
--   fixes it and no code changes.
--
--   POLICY problem -- the RLS policy on `clients` grants a team_lead only the
--   engagements where is_team_lead is true, while granting a consultant every
--   engagement they are assigned to. If that is how it is written, then even
--   after moving the rows a Team Lead still would not see the ones where they
--   are just a specialist -- and that would bite every other Team Lead too,
--   not only you.
--
-- The `using_expression` column below is the answer. Look at the policy on
-- `clients` for SELECT:
--
--   * if it tests only for membership -- something like
--     "exists (select 1 from client_assignments where client_id = clients.id
--      and user_id = auth.uid())" -- then the policy is already correct and
--     this is purely a data merge.
--
--   * if it also tests is_team_lead, or branches on the user's role, then the
--     policy itself is what needs changing.
--
-- The policies on clients predate migration 017, so they are not in the repo
-- and this is the only way to read them.

select
  p.tablename,
  p.policyname,
  p.cmd                        as applies_to,
  p.permissive,
  array_to_string(p.roles, ', ') as db_roles,
  p.qual                       as using_expression,
  p.with_check                 as with_check_expression
from pg_policies p
where p.schemaname = 'public'
  and p.tablename in (
    'clients',
    'client_assignments',
    'time_entries',
    'client_documents',
    'client_research_questions',
    'users'
  )
order by
  case p.tablename
    when 'clients' then 1
    when 'client_assignments' then 2
    else 3
  end,
  p.tablename,
  p.cmd,
  p.policyname;
