-- 119_application_notifications_on_real_table.sql
--
-- Depends on 023_client_closed_notifications.sql (notifications),
-- 073_application_submitted_notifications.sql (the original trigger),
-- 082_notification_recipients.sql (notification_recipients + RLS) and
-- 111_public_application_submitted_by_nullable.sql.
--
-- Greg (9/14/26): "i just submitted an application and i'm logged in as
-- Admin. i did not get a notification. Every admin needs to get an email
-- notification and a bell notification when a new application is submitted."
--
-- WHY NO BELL FIRED
-- 073 put trg_notify_application_submitted on client_application_drafts,
-- firing when source = 'public_application'. That was correct at the time:
-- public-submit-application inserted a DRAFT. On 9/4/26 that function was
-- rewritten to insert straight into client_applications instead (see
-- 111 and the function's own header). The trigger was never moved, so
-- since 9/4 every public submission has landed in a table nothing was
-- watching. No bell for anyone, silently -- the submission itself worked,
-- which is why this went unnoticed.
--
-- client_applications has no `source` column and no `engagement_name`; the
-- equivalents are submitted_by (null for a public submission, per 111) and
-- company_name. So this is a new function against the new table rather than
-- a patch of the old one -- the old one still type-checks only against
-- client_application_drafts.
--
-- WHO GETS IT
-- Every Admin (users.role = 'super_admin' -- what the UI labels "Admin"),
-- which is what 073/082 already intended, except the submitter themselves
-- when there is one. An internal wizard submission is made BY an admin, and
-- a bell telling you about the thing you just typed is noise. A public
-- submission has submitted_by null, so nobody is excluded and every admin
-- gets it -- the case Greg hit.
--
-- WHAT ABOUT THE OLD TRIGGER
-- Left in place on client_application_drafts. Nothing inserts a draft with
-- source = 'public_application' any more (the only writer was the Edge
-- Function), so it cannot double-fire; and if some path ever does again, a
-- bell is the behaviour we want anyway.
--
-- The message drops "waiting in Drafts" -- submissions have not been drafts
-- since 9/4 and the wording sent admins to the wrong place.
--
-- Email is the other half of Greg's request and is NOT here: it is sent by
-- the public-submit-application Edge Function via Resend, not by the
-- database. That change ships with the function.
--
-- Safe to re-run.

create or replace function notify_client_application_submitted()
returns trigger
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_program_name text;
  v_notification_id uuid;
begin
  select name into v_program_name
  from econ_dev_companies
  where id = NEW.econ_dev_company_id;

  insert into notifications (type, client_id, message)
  values (
    'application_submitted',
    null,
    'New Application: ' || coalesce(nullif(trim(NEW.company_name), ''), 'Unnamed company')
      || case when v_program_name is not null then ' via ' || v_program_name else '' end
      || ' -- waiting on Engagement Applications.'
  )
  returning id into v_notification_id;

  -- Every Admin except whoever submitted it. NEW.submitted_by is null for a
  -- public submission, and `u.id is distinct from null` is true, so a public
  -- submission reaches every admin.
  insert into notification_recipients (notification_id, user_id)
  select v_notification_id, u.id
  from users u
  where u.role = 'super_admin'
    and u.id is distinct from NEW.submitted_by
  on conflict (notification_id, user_id) do nothing;

  return NEW;
end;
$$;

drop trigger if exists trg_notify_client_application_submitted on client_applications;
create trigger trg_notify_client_application_submitted
after insert on client_applications
for each row execute function notify_client_application_submitted();

-- ---------------------------------------------------------------
-- Backfill: any application submitted since the 9/4 rewrite got no bell at
-- all. Give the admins one for each of those still sitting in 'pending', so
-- nothing that arrived during the gap stays invisible. Matched on the
-- message text so re-running this file cannot produce duplicates.
-- ---------------------------------------------------------------
do $$
declare
  r record;
  v_msg text;
  v_id  uuid;
begin
  for r in
    select a.id, a.company_name, a.submitted_by, a.submitted_at, c.name as program_name
    from client_applications a
    left join econ_dev_companies c on c.id = a.econ_dev_company_id
    where a.status = 'pending'
      and a.submitted_at >= timestamptz '2026-09-04'
    order by a.submitted_at
  loop
    v_msg := 'New Application: ' || coalesce(nullif(trim(r.company_name), ''), 'Unnamed company')
      || case when r.program_name is not null then ' via ' || r.program_name else '' end
      || ' -- waiting on Engagement Applications.';

    if exists (select 1 from notifications n where n.message = v_msg) then
      continue;
    end if;

    insert into notifications (type, client_id, message)
    values ('application_submitted', null, v_msg)
    returning id into v_id;

    insert into notification_recipients (notification_id, user_id)
    select v_id, u.id
    from users u
    where u.role = 'super_admin'
      and u.id is distinct from r.submitted_by
    on conflict (notification_id, user_id) do nothing;
  end loop;
end $$;

-- ---------------------------------------------------------------
-- Verify. Expect one row per admin per recent application, all unread.
-- ---------------------------------------------------------------
select
  n.created_at,
  n.message,
  count(nr.user_id)                                  as admins_notified,
  count(nr.user_id) filter (where nr.read_at is null) as still_unread
from notifications n
left join notification_recipients nr on nr.notification_id = n.id
where n.type = 'application_submitted'
group by n.id, n.created_at, n.message
order by n.created_at desc
limit 20;
