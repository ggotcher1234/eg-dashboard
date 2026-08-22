-- 073_application_submitted_notifications.sql
--
-- Depends on 023_client_closed_notifications.sql (notifications table),
-- 048_client_application_drafts.sql / 066_public_program_applications.sql
-- (client_application_drafts table, its `source` and `econ_dev_company_id`
-- columns).
--
-- Greg (8/22/26): a public Program-application submission goes through the
-- public-submit-application Edge Function, which emails Chris, Rita, and
-- Greg via Resend -- but that email can fail silently (e.g. Resend's shared
-- onboarding@resend.dev sending domain only delivers to the Resend
-- account's own verified address until a real domain is verified, so a
-- send to other recipients gets rejected). When it does, nothing in the
-- app told anyone a new application had shown up.
--
-- This adds an in-app bell notification as a second, always-reliable
-- channel: an AFTER INSERT trigger on client_application_drafts fires
-- whenever a row lands with source = 'public_application', regardless of
-- whether the email send succeeded or failed. Same pattern as
-- notify_client_closed() in 023 -- security definer + row_security off, so
-- it fires correctly even though the public Edge Function inserts via the
-- service-role client.
--
-- Safe to re-run.

create or replace function notify_application_submitted()
returns trigger
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_program_name text;
begin
  if NEW.source = 'public_application' then
    select name into v_program_name from econ_dev_companies where id = NEW.econ_dev_company_id;
    insert into notifications (type, client_id, message)
    values (
      'application_submitted',
      null,
      'New Application: ' || coalesce(nullif(trim(NEW.engagement_name), ''), 'Unnamed company')
        || case when v_program_name is not null then ' via ' || v_program_name else '' end
        || ' -- waiting in Drafts on Engagement Applications.'
    );
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_notify_application_submitted on client_application_drafts;
create trigger trg_notify_application_submitted
after insert on client_application_drafts
for each row execute function notify_application_submitted();
