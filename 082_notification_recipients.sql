-- 082_notification_recipients.sql
--
-- Depends on 023_client_closed_notifications.sql (notifications table),
-- 073_application_submitted_notifications.sql, 078_evaluation_responses.sql
-- (notify_evaluation_submitted()), 040_client_team_partner_contacts.sql +
-- 039_econ_dev_partner_contacts.sql (Program Contact / partner-contact
-- records).
--
-- Greg (8/25/26): "i just want to make sure that the notification bell
-- goes to everyone on the engagement team from EG and the Program manager
-- if they have an account."
--
-- Until now `notifications` had exactly one audience -- Super Admins --
-- via a blanket `is_super_admin()` RLS policy, and a single shared
-- read_at/read_by pair (fine when only Super Admins ever saw a row, but
-- wrong the moment more than one person can see the same notification:
-- one person dismissing it would make it vanish for everyone else too).
--
-- This adds a proper per-recipient fan-out:
--   1. notification_recipients -- one row per (notification, user), each
--      with its own read_at, so dismissing a notification only affects
--      the person who dismissed it.
--   2. notifications' RLS now checks notification_recipients instead of
--      is_super_admin() directly -- you see a notification only if you
--      were actually added as a recipient.
--   3. All three trigger functions (notify_client_closed,
--      notify_application_submitted, notify_evaluation_submitted) now
--      insert the matching recipient rows after inserting the
--      notification. client_closed and application_submitted keep their
--      existing audience (Super Admins only -- nothing changes for
--      those). evaluation_submitted's audience widens to:
--        - everyone on that client's EG engagement team
--          (client_assignments.user_id for that client, wherever a real
--          account is filled into the slot -- Team Lead, specialists,
--          Admin/QC),
--        - the client's Program Contact/"Program Manager"
--          (client_team_partner_contacts -> econ_dev_partner_contacts),
--          but ONLY if that person also happens to have a login account
--          in this app (matched by email) -- partner contacts are just
--          directory entries with no account by default, so this is a
--          best-effort match, not a guarantee,
--        - Super Admins, same as before.
--   4. A one-time backfill inserts Super-Admin recipient rows for any
--      currently-unread notifications, so nothing already sitting in an
--      admin's bell silently disappears the moment this ships.
--
-- Safe to re-run.

create table if not exists notification_recipients (
  id              uuid primary key default gen_random_uuid(),
  notification_id uuid not null references notifications(id) on delete cascade,
  user_id         uuid not null references users(id) on delete cascade,
  read_at         timestamptz,
  created_at      timestamptz not null default now(),
  unique (notification_id, user_id)
);

create index if not exists idx_notification_recipients_unread
  on notification_recipients(user_id) where read_at is null;

alter table notification_recipients enable row level security;

drop policy if exists notification_recipients_select on notification_recipients;
create policy notification_recipients_select on notification_recipients for select
using ( user_id = auth.uid() );

drop policy if exists notification_recipients_update on notification_recipients;
create policy notification_recipients_update on notification_recipients for update
using ( user_id = auth.uid() )
with check ( user_id = auth.uid() );

-- No insert/delete policy for regular roles on purpose -- rows are written
-- only by the security-definer trigger functions below (row_security off),
-- same pattern as notifications itself in 023.

-- ---------- notifications RLS: now recipient-scoped, not admin-blanket ----------
drop policy if exists notifications_select on notifications;
create policy notifications_select on notifications for select
using (
  exists (
    select 1 from notification_recipients nr
    where nr.notification_id = notifications.id and nr.user_id = auth.uid()
  )
);

-- The old per-row read_at/read_by on notifications is no longer written by
-- the app (read state now lives on notification_recipients, per person),
-- so the update policy that used to let Super Admins flip it is dropped.
drop policy if exists notifications_update on notifications;

-- ---------- notify_client_closed(): unchanged audience (Super Admins) ----------
create or replace function notify_client_closed()
returns trigger
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_actor_name text;
  v_notification_id uuid;
begin
  if NEW.project_status = 'closed' and OLD.project_status is distinct from 'closed' then
    select full_name into v_actor_name from users where id = auth.uid();
    insert into notifications (type, client_id, message)
    values (
      'client_closed',
      NEW.id,
      coalesce(v_actor_name, 'Someone') || ' closed ' || NEW.name || ' -- ready to be reassigned.'
    )
    returning id into v_notification_id;

    insert into notification_recipients (notification_id, user_id)
    select v_notification_id, u.id from users u where u.role = 'super_admin'
    on conflict (notification_id, user_id) do nothing;
  end if;
  return NEW;
end;
$$;

-- ---------- notify_application_submitted(): unchanged audience (Super Admins) ----------
create or replace function notify_application_submitted()
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
  if NEW.source = 'public_application' then
    select name into v_program_name from econ_dev_companies where id = NEW.econ_dev_company_id;
    insert into notifications (type, client_id, message)
    values (
      'application_submitted',
      null,
      'New Application: ' || coalesce(nullif(trim(NEW.engagement_name), ''), 'Unnamed company')
        || case when v_program_name is not null then ' via ' || v_program_name else '' end
        || ' -- waiting in Drafts on Engagement Applications.'
    )
    returning id into v_notification_id;

    insert into notification_recipients (notification_id, user_id)
    select v_notification_id, u.id from users u where u.role = 'super_admin'
    on conflict (notification_id, user_id) do nothing;
  end if;
  return NEW;
end;
$$;

-- ---------- notify_evaluation_submitted(): widened audience ----------
create or replace function notify_evaluation_submitted()
returns trigger
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_client_name text;
  v_notification_id uuid;
begin
  select name into v_client_name from clients where id = NEW.client_id;
  insert into notifications (type, client_id, message)
  values (
    'evaluation_submitted',
    NEW.client_id,
    coalesce(v_client_name, 'A client') || '''s Close-Out Evaluation was just submitted -- ready to review.'
  )
  returning id into v_notification_id;

  insert into notification_recipients (notification_id, user_id)
  select v_notification_id, uid from (
    -- everyone on this client's EG engagement team with a real account
    -- in the slot (Team Lead, specialists, Admin/QC)
    select ca.user_id as uid
    from client_assignments ca
    where ca.client_id = NEW.client_id and ca.user_id is not null

    union

    -- the client's Program Contact/"Program Manager", only if that
    -- contact also happens to have a login account (matched by email)
    select u2.id as uid
    from client_team_partner_contacts ctpc
    join econ_dev_partner_contacts epc on epc.id = ctpc.partner_contact_id
    join users u2 on lower(u2.email) = lower(epc.email)
    where ctpc.client_id = NEW.client_id and epc.email is not null

    union

    -- Super Admins, same as every other notification type
    select u3.id as uid from users u3 where u3.role = 'super_admin'
  ) recipients
  on conflict (notification_id, user_id) do nothing;

  return NEW;
end;
$$;

drop trigger if exists trg_notify_evaluation_submitted on client_evaluation_responses;
create trigger trg_notify_evaluation_submitted
after insert on client_evaluation_responses
for each row execute function notify_evaluation_submitted();

-- ---------- one-time backfill ----------
-- Anything already unread keeps showing for Super Admins after this ships
-- (nothing currently in the bell should silently vanish).
insert into notification_recipients (notification_id, user_id)
select n.id, u.id
from notifications n
cross join users u
where n.read_at is null and u.role = 'super_admin'
on conflict (notification_id, user_id) do nothing;
