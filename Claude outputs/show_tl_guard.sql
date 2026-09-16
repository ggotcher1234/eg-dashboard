-- show_tl_guard.sql   (9/16/26)
--
-- Read-only. One statement, one grid.
--
-- The merge was stopped by a trigger, not a constraint:
--
--   ERROR: Only a Super Admin can assign a client's Team Lead
--          (Assign TL, Section 4.1)
--   CONTEXT: PL/pgSQL function enforce_team_lead_assignment() line 4
--
-- That guard is doing its job. The SQL editor connects as the `postgres`
-- role with no end-user JWT attached, so anything the function checks about
-- "who is doing this" -- typically auth.uid() against users.role -- comes back
-- null, and null is not a Super Admin.
--
-- There are a few ways around that and they are not equally safe. Disabling
-- the trigger is the worst of them: it is a rule somebody wrote deliberately,
-- and turning it off leaves a window where any row can move. The right fix is
-- to satisfy the check rather than remove it -- but to do that I need to see
-- exactly what it tests, which differs between implementations.
--
-- The function is not in the repo (it predates migration 017), so this is the
-- only way to read it.

select
  p.proname                                as function_name,
  pg_get_functiondef(p.oid)                as source
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where p.proname in (
        'enforce_team_lead_assignment',
        'enforce_super_admin_user_fields'
      )
  and n.nspname = 'public';
