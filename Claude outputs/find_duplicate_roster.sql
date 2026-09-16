-- find_duplicate_roster.sql   (9/16/26)
--
-- Read-only. Changes nothing.
--
-- The Team Lead dropdown showed "Chris Gibbons (Admin)" twice and
-- "Rita Benson (Admin)" twice. Two rows, same person. That is worth
-- understanding before go-live, because duplicate people are exactly what
-- made this morning's engagement-visibility puzzle so hard to read: work
-- lands on one row while you are looking at the other.
--
-- This lists every name that appears more than once on the roster, with
-- enough context to tell you which copy is the live one:
--
--   assignments   how many engagements that row is on
--   hours_logged  how many time entries are attached to it
--   last_signed_in  whether anybody has ever used that login
--
-- The usual pattern is one row doing all the work and a twin with zeroes
-- everywhere -- that twin is the safe one to remove. If BOTH rows have
-- assignments or hours, do not delete either; they need merging the way
-- Greg's own accounts were merged earlier today.

select
  pu.full_name,
  au.email,
  pu.id                                   as user_id,
  pu.role::text                           as eg_role,
  count(distinct a.id)                    as assignments,
  count(distinct t.id)                    as hours_logged,
  au.last_sign_in_at                      as last_signed_in,
  au.created_at                           as account_created,
  case
    when count(distinct a.id) = 0 and count(distinct t.id) = 0
         and au.last_sign_in_at is null
      then 'UNUSED -- safe to remove'
    when count(distinct a.id) = 0 and count(distinct t.id) = 0
      then 'no work attached, but has been signed into'
    else 'IN USE -- do not delete, merge instead'
  end                                     as verdict
from public.users pu
join auth.users au on au.id = pu.id
left join public.client_assignments a on a.user_id = pu.id
left join public.time_entries       t on t.consultant_id = pu.id
where lower(btrim(pu.full_name)) in (
  select lower(btrim(full_name))
  from public.users
  group by lower(btrim(full_name))
  having count(*) > 1
)
group by pu.full_name, au.email, pu.id, pu.role, au.last_sign_in_at, au.created_at
order by lower(btrim(pu.full_name)), au.created_at;
