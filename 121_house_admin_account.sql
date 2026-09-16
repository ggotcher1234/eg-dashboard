-- 121_house_admin_account.sql
--
-- Depends on 074_program_admin_qc_billing_model.sql (bill_admin_qc_upfront)
-- and 108_hidden_from_roster.sql (hidden_from_roster).
--
-- Rita (9/14/26, item 4): "Engagement workspace doesn't allow me to add hours
-- for admin and QC for when the hours need to be billed at the end of the
-- engagement. GRE exception."
--
-- WHY IT DOESN'T
-- 074 gave GRE what it asked for -- Admin and QC billed as performed, with a
-- real Log Hours button -- but accept_client_application creates those two
-- rows UNASSIGNED, and the button only appears once somebody is on the row:
--
--   canLogHours = !isSunkCost && !!person && (isSuperAdmin || person.id === currentUser.id)
--                                ^^^^^^^^^
--
-- So on a GRE engagement nobody could log Admin or QC hours at all, and
-- GRE's invoice was quietly short by those hours. That matters in October,
-- when the whole point of the parallel run is the invoice matching Podio.
--
-- WHY A HOUSE ACCOUNT RATHER THAN A PERSON
-- Greg (9/16/26): "only Rita can change the admin and QC hours but i don't
-- want her name appearing in the assigned to area." Admin and QC are house
-- work, not an individual's assignment -- naming whoever happened to do them
-- would put a person on the engagement team who isn't really on it, and that
-- name then flows into Pay Statements and the hours rollup.
--
-- A single hidden account solves all three constraints WITHOUT new permission
-- logic, which is the part worth noticing:
--
--   * the Person column reads "NCEG Admin", not Rita
--   * hidden_from_roster keeps it out of every pick list already
--   * only Admins can log against it, for free -- the existing rule is
--     `isSuperAdmin || person.id === currentUser.id`. Rita passes the first
--     clause. A Team Lead fails both, because they are not NCEG Admin.
--
-- WHY A TRIGGER RATHER THAN EDITING accept_client_application
-- That function is long, has been revised several times (025, 110), and
-- builds every engagement there is. A BEFORE INSERT trigger on
-- client_assignments is a few lines, cannot break the accept path, and also
-- catches Admin/QC rows added later from "+ Add work area" -- which editing
-- the accept function would have missed.
--
-- Deliberately INSERT only. If someone unassigns the house account from a row
-- on purpose, it stays unassigned; an UPDATE does not re-fill it.
--
-- Safe to re-run.

-- ---------------------------------------------------------------
-- 1. Mark which account is the house account.
--
-- A flag rather than a hardcoded id or email, so the account can be renamed
-- or replaced without touching this function again.
-- ---------------------------------------------------------------
alter table users add column if not exists is_house_account boolean not null default false;

comment on column users.is_house_account is
  'True for the single non-person account that owns house work (Admin, Quality
   Control) on engagements. Kept hidden_from_roster so it never appears in
   pick lists. Rita/Greg, 9/16/26.';

-- Only ever one. A partial unique index is the cheapest way to say so.
create unique index if not exists users_one_house_account
  on users ((true)) where is_house_account;

-- ---------------------------------------------------------------
-- 2. New Admin / QC rows get the house account automatically.
-- ---------------------------------------------------------------
create or replace function assign_house_account_to_house_work()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_house uuid;
begin
  if NEW.user_id is null and NEW.specialty_type in ('admin', 'quality_control') then
    select id into v_house from users where is_house_account limit 1;
    if v_house is not null then
      NEW.user_id := v_house;
    end if;
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_assign_house_account on client_assignments;
create trigger trg_assign_house_account
before insert on client_assignments
for each row execute function assign_house_account_to_house_work();

-- ---------------------------------------------------------------
-- 3. Point the flag at the NCEG Admin account, and backfill the engagements
--    that already exist.
--
-- The account itself is made from the UI, not here -- Roster -> Add Roster
-- Member, name "NCEG Admin", role Specialist, email admin@economicgardening.org
-- (it never signs in). Done on 9/16/26. This file only flags it, so a rebuilt
-- database that has not had that account created yet says so and changes
-- nothing rather than half-applying.
--
-- The backfill touches only rows nobody has claimed. If a real person was put
-- on an Admin or QC row deliberately, they stay.
--
-- Applied 9/16/26: flagged NCEG Admin, backfilled 14 rows.
-- ---------------------------------------------------------------
do $$
declare
  v_house uuid;
  n int;
begin
  update users
     set is_house_account   = true,
         hidden_from_roster = true
   where lower(email) = 'admin@economicgardening.org'
  returning id into v_house;

  if v_house is null then
    select id into v_house from users where is_house_account limit 1;
  end if;

  if v_house is null then
    raise notice
      'No house account yet. Create "NCEG Admin" (admin@economicgardening.org) on the Roster, then re-run this file. Nothing was changed.';
    return;
  end if;

  update client_assignments
     set user_id = v_house
   where user_id is null
     and specialty_type in ('admin', 'quality_control');
  get diagnostics n = row_count;
  raise notice 'House account set. Backfilled % Admin/QC row(s).', n;
end $$;

-- ---------------------------------------------------------------
-- Verify. Expect one house account, and no unassigned Admin/QC rows.
-- ---------------------------------------------------------------
select
  (select count(*) from users where is_house_account)                     as house_accounts,
  (select full_name from users where is_house_account limit 1)            as house_account_name,
  (select count(*) from client_assignments
    where user_id is null and specialty_type in ('admin','quality_control')) as still_unassigned;
