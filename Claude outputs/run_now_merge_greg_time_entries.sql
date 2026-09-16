-- run_now_merge_greg_time_entries.sql   (9/16/26)
--
-- OPTIONAL. Read the note below and decide before running.
--
-- Earlier today we merged Greg's three logins: assignments and team
-- membership moved onto the Team Lead account
-- (greg.gotcher@leadforcesolutions.com). time_entries.consultant_id was NOT
-- moved, because until now nothing read it -- invoicing attributed hours by
-- whoever held the assignment row, so the old ids were invisible.
--
-- The invoicing fix changes that. Pay is now credited to whoever logged the
-- work, which is correct, and the side effect is that Greg's hours split
-- across two accounts:
--
--   greg@leadforcesolutions.com          super_admin, hidden   15 h
--   greg.gotcher@leadforcesolutions.com  team_lead             21 h
--
-- So August's Pay Statements will list "Greg Gotcher" twice, 15 h and 21 h,
-- instead of once at 36 h. Two lines, same person, same money -- wrong on a
-- statement and very confusing in a review meeting.
--
-- THINK BEFORE RUNNING. The super_admin account is Greg-as-Chris/Rita's-peer
-- (hidden admin), the team_lead account is Greg-as-Team-Lead. If those 15
-- hours were genuinely admin work rather than Team Lead work, they may belong
-- on a separate line and you should NOT run this. If, as looks likely, it is
-- just one person who logged from whichever login he happened to be in, merge
-- them.
--
-- Only touches time_entries.consultant_id. Assignments, hours, dates, notes
-- and both logins are untouched -- the admin account keeps working.
--
-- Safe to re-run: the second run moves 0 rows.

do $$
declare
  v_from uuid;
  v_to   uuid;
  n      int;
begin
  select id into v_from from users where lower(email) = 'greg@leadforcesolutions.com';
  select id into v_to   from users where lower(email) = 'greg.gotcher@leadforcesolutions.com';

  if v_from is null or v_to is null then
    raise exception 'One of the two Greg accounts is missing. Nothing was changed.';
  end if;

  update time_entries
     set consultant_id = v_to
   where consultant_id = v_from;
  get diagnostics n = row_count;

  raise notice 'Moved % time entr(ies) onto the Team Lead account.', n;
end $$;

-- Expect one Greg Gotcher row with hours, and 36 total.
select
  u.email,
  u.role::text                      as eg_role,
  count(t.id)                       as entries,
  coalesce(sum(t.hours), 0)         as hours
from users u
left join time_entries t on t.consultant_id = u.id
where u.full_name ilike '%Gotcher%'
group by u.email, u.role
order by 4 desc;
