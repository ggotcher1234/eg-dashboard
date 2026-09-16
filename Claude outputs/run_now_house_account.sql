-- run_now_house_account.sql   (9/16/26)
--
-- Run this AFTER creating the roster member:
--   Roster -> Add Roster Member
--   Name  NCEG Admin     Role  Specialist
--   Email admin@economicgardening.org
--
-- You do NOT need the "Hide from Roster" checkbox. This sets it.
--
-- Assumes 121_house_admin_account.sql has already been run once (it has --
-- that is the run that reported 0 house accounts and 14 unassigned rows).
--
-- If the account does not exist yet, this changes nothing and says so.

do $$
declare
  v_house uuid;
  n int;
begin
  select id into v_house
  from users
  where lower(email) = 'admin@economicgardening.org';

  if v_house is null then
    raise exception
      'No roster member with that email yet. Create "NCEG Admin" on the Roster first, then run this again. Nothing was changed.';
  end if;

  update users
     set is_house_account   = true,
         hidden_from_roster = true
   where id = v_house;

  update client_assignments
     set user_id = v_house
   where user_id is null
     and specialty_type in ('admin', 'quality_control');
  get diagnostics n = row_count;

  raise notice 'NCEG Admin is now the house account. Backfilled % Admin/QC row(s).', n;
end $$;

-- Expect: NCEG Admin, and 0 still unassigned.
select
  (select full_name from users where is_house_account limit 1)            as house_account,
  (select count(*) from client_assignments
    where user_id is null and specialty_type in ('admin','quality_control')) as still_unassigned;
