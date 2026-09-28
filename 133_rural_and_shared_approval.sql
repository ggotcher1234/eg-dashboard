-- 133_rural_and_shared_approval.sql   (9/28/26)
--
-- Chris (9/28/26, relayed by Greg), correcting the sequence:
--
--   "in step 2, Rita approves the application using her five criteria. I only
--    get involved if the application gets messy. Either of us needs to be
--    able to approve."
--   "3. Rita checks for five criteria, and checks box for NCEG approval.
--    Either one of us can check that approval (add another check box for
--    'rural'. We have different criteria: $650,000 and 6)."
--
-- TWO CHANGES, AND THEY UNDO PART OF 129.
--
-- 1. APPROVAL IS SHARED. 129 gave the approval to one person because the
--    procedure as described on 9/25/26 had Chris approving first and Rita
--    blocked until he had. That is not the procedure -- Chris is the
--    exception handler, not the first gate. So Rita holds it too, and the
--    ORDER changes in the page: the five thresholds come first and the
--    approval box is what they unlock, rather than the other way round.
--    Nothing in the schema enforced the old order, so nothing here has to
--    undo it; users.can_approve_applications simply has two holders now.
--
-- 2. RURAL APPLICANTS ARE JUDGED ON A DIFFERENT BAR. $650,000 in sales and 6
--    employees, rather than $1M and 10. This is a property of the
--    APPLICATION, not of the Program -- a rural company can come through a
--    Program that is mostly metro -- so it lives here and is decided by
--    whoever reviews it.
--
-- WHY is_rural IS STORED RATHER THAN DERIVED
-- There is no field on the application that says rural, and no defensible
-- way to infer it: county and postal code get you a guess, and a guess that
-- silently changes which financial bar a company is held to is worse than
-- asking. So it is a tick, it defaults to false, and the record shows which
-- bar the company actually cleared -- which is the fact anyone looking back
-- at a marginal approval will want.
--
-- Safe to re-run. Depends on 129 and 131.

-- ---------- 1. the rural flag ----------
alter table client_applications
  add column if not exists is_rural boolean not null default false;

comment on column client_applications.is_rural is
  'This applicant is judged against the rural thresholds -- $650,000 in sales and 6 employees, rather than $1M and 10 (Chris, 9/28/26). Ticked on the Accept form by whoever reviews it; there is no field on the application this can be inferred from. Stored so the record shows which bar the company was held to.';

-- ---------- 2. Rita holds the approval too ----------
-- Seeded by pattern, the same way 128 and 129 seeded Chris, and for the same
-- reason: on the day this ships the right people have to already hold it or
-- the Applications tab is blocked with nobody able to unblock it. After
-- today it is a tick on a Roster profile -- "Can approve applications" --
-- and no name needs to appear in a file again.
do $$
declare
  n int;
begin
  update users
     set can_approve_applications = true
   where archived_at is null
     and role = 'super_admin'
     and (email ilike 'rbenson@%' or full_name ~* '\mrita\M.*\mbenson\M')
     and not can_approve_applications;
  get diagnostics n = row_count;
  raise notice 'Granted approval rights to % further account(s).', n;
end $$;

-- Expect exactly two holders: Chris and Rita, both on their work accounts.
-- More than two, or a gmail duplicate in the list, wants looking at.
select
  full_name,
  email,
  can_approve_applications as can_approve,
  cc_on_client_email       as cc_on_client,
  hidden_from_roster,
  archived_at is not null  as archived
from users
where role = 'super_admin' or can_approve_applications
order by can_approve_applications desc, full_name;

-- ---------- 3. what the rural bar would change, if anything ----------
-- Nothing is backfilled -- is_rural is a judgment nobody has made yet. This
-- is just a look at the pending applications and whether the rural bar would
-- move any of them, so the flag lands on the ones that need it.
select
  a.company_name,
  edc.code                                            as program,
  a.address->>'county'                                as county,
  a.fte_2025,
  a.revenue_2025,
  (coalesce(a.fte_2025, 0) >= 10)                     as meets_standard_fte,
  (coalesce(a.fte_2025, 0) >= 6)                      as meets_rural_fte,
  (coalesce(a.revenue_2025, 0) >= 1000000)            as meets_standard_sales,
  (coalesce(a.revenue_2025, 0) >= 650000)             as meets_rural_sales
from client_applications a
left join econ_dev_companies edc on edc.id = a.econ_dev_company_id
where a.status = 'pending'
order by a.submitted_at desc;
