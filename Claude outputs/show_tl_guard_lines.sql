-- show_tl_guard_lines.sql   (9/16/26)
--
-- Read-only. One statement, one grid.
--
-- Same question as before, readable this time. The previous version returned
-- the whole function body in a single cell and the results grid cut it off at
-- the column width, so neither of us could actually read it.
--
-- This splits the source on newlines and returns one row per line, which the
-- grid shows in full. Paste the whole thing back.

select
  p.proname                as fn,
  l.ord                    as line,
  l.txt                    as code
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral unnest(string_to_array(pg_get_functiondef(p.oid), E'\n'))
       with ordinality as l(txt, ord)
where p.proname = 'enforce_team_lead_assignment'
  and n.nspname = 'public'
order by l.ord;
