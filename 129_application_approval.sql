-- 129_application_approval.sql   (9/25/26)
--
-- Greg (9/25/26, from the call): "when an application is submitted, Chris
-- needs to approve it. We want a checkbox on the bottom of the form where the
-- hours/TL assignments are that says Approved by Chris Gibbons. Only he can
-- check it. When he checks it an email needs to go out to the PA and Rita
-- letting them know that the new Applicant (Name) has been approved on
-- 'date'. Then Rita will go in and add the hours and TL which will kick off
-- the engagement for the EG Team."
--
-- WHAT CHANGES
-- Accepting an application is two decisions today pretending to be one. "Is
-- this company a fit for the program" is Chris's call; "who runs it and with
-- how many hours" is Rita's. Both happen in the same Accept box, in whatever
-- order somebody gets to it, with nothing recorded about the first one at all.
-- This splits them: an application carries an approval (a date and a person),
-- and the assignment half of the form stays disabled until it has one.
--
-- WHY A FLAG AND NOT "CHRIS"
-- Same reasoning as 128_cc_on_client_email.sql, which removed the last
-- hardcoded name from this app a few hours ago. Writing `email = 'cgibbons@%'`
-- into the check would mean Chris cannot hand this off for a fortnight, cannot
-- be covered when he is away, and cannot be replaced without a deploy. So it
-- is a property of a person -- ticked on their Roster profile -- and the
-- checkbox label reads the name back OUT of the flag. It still says "Approved
-- by Chris Gibbons" on screen, because Chris is who holds it.
--
-- WHERE IT IS ENFORCED
-- In the admin-approve-application Edge Function, which proves the caller
-- holds the flag before it writes, and is also the only thing that can send
-- the notification (the Resend key lives there and nowhere else). Same shape
-- as archiving in 125: one server-side gate rather than a gate plus a policy
-- that can drift apart.
--
-- Deliberately NOT a trigger on the table. Every Admin already has blanket
-- UPDATE on client_applications -- they accept, archive and edit these rows
-- all day -- so a trigger would only be stopping people who can already do
-- strictly more damage through the front door. It would cost a second place
-- for the rule to live, and buy nothing.
--
-- EXISTING APPLICATIONS are left unapproved, on purpose. Backfilling
-- approved_at on the ones already accepted would put Chris's name and a date
-- on decisions this column did not exist for. Anything still pending genuinely
-- does now need his tick -- that is the point of the change, not a side
-- effect of it.
--
-- Safe to re-run.

-- ---------- 1. the approval, on the application ----------
alter table client_applications
  add column if not exists approved_at timestamptz,
  add column if not exists approved_by uuid references users(id) on delete set null;

comment on column client_applications.approved_at is
  'When this application was approved for the program. Null = not yet approved, and the Accept form''s hours/Team Lead/Accept controls stay disabled. Set by the admin-approve-application Edge Function, which requires users.can_approve_applications.';

comment on column client_applications.approved_by is
  'Who approved it. ON DELETE SET NULL so removing an account never erases the fact of the approval -- approved_at is the part that gates the form.';

-- ---------- 2. who may approve ----------
alter table users
  add column if not exists can_approve_applications boolean not null default false;

comment on column users.can_approve_applications is
  'This person may approve incoming applications (the "Approved by ..." checkbox on the Accept form), and their name is what that checkbox reads. Ticked per person on the Roster profile by an Admin. Today: Chris.';

-- ---------- 3. seed ----------
-- The same match 128 used, for the same reason: the rule is about to be a
-- tick on a profile, but on the day it ships the right person has to already
-- hold it or the whole Applications tab is blocked with nobody able to
-- unblock it.
do $$
declare
  n int;
begin
  update users
     set can_approve_applications = true
   where archived_at is null
     and (email ilike 'cgibbons@%' or full_name ~* '\mchris(topher)?\M.*\mgibbons\M');
  get diagnostics n = row_count;

  if n = 0 then
    raise warning
      'Nobody was matched, so NO ONE can approve an application and every pending one is stuck. Tick "Can approve applications" on the right Roster profile before anyone tries to accept.';
  else
    raise notice 'Granted approval rights to % account(s).', n;
  end if;
end $$;

-- Note the duplicate accounts: Chris has (had) a second gmail login, and if
-- both matched above, both now carry the flag, and the checkbox label would
-- read his name twice. Archiving the duplicate -- which is already on Greg's
-- list -- takes care of it; the listing below is how you spot it.

-- ---------- 4. what to check ----------
-- Expect exactly one row with can_approve = true.
select
  full_name,
  email,
  role::text                  as eg_role,
  can_approve_applications    as can_approve,
  cc_on_client_email          as cc_on_client,
  hidden_from_roster,
  archived_at is not null     as archived
from users
where role = 'super_admin' or can_approve_applications
order by can_approve_applications desc, full_name;

-- Pending applications now waiting on an approval -- these are the ones that
-- will show the disabled form until the box is ticked.
select
  a.company_name,
  edc.code                      as program,
  a.submitted_at,
  a.approved_at
from client_applications a
left join econ_dev_companies edc on edc.id = a.econ_dev_company_id
where a.status = 'pending'
order by a.submitted_at desc;
