-- 023_client_closed_notifications.sql
--
-- Depends on 001_foundation_schema.sql (is_super_admin(), users, clients,
-- project_status_type).
--
-- When a Team Lead marks a client Closed on the Client Workspace page
-- (or a Super Admin does, or it happens via the Applications page's
-- project-status toggle -- any path that flips clients.project_status to
-- 'closed'), Super Admins should see an in-app notification so they know
-- that Team Lead is free to be assigned another client.
--
-- Implemented as an AFTER UPDATE trigger on clients rather than
-- client-side inserts, so it fires reliably no matter which screen made
-- the change. The trigger function is security definer + row_security
-- off (same pattern as 018/021/022) because it needs to write a
-- notifications row regardless of who -- Team Lead or Super Admin --
-- triggered the update, and Supabase Cloud's function-owning role is not
-- a true superuser so RLS still applies inside definer functions unless
-- explicitly turned off.
--
-- Safe to re-run.

create table if not exists notifications (
  id         uuid primary key default gen_random_uuid(),
  type       text not null,
  client_id  uuid references clients(id) on delete cascade,
  message    text not null,
  created_at timestamptz not null default now(),
  read_at    timestamptz,
  read_by    uuid references users(id)
);

create index if not exists idx_notifications_unread on notifications(read_at) where read_at is null;

alter table notifications enable row level security;

drop policy if exists notifications_select on notifications;
create policy notifications_select on notifications for select
using ( is_super_admin() );

drop policy if exists notifications_update on notifications;
create policy notifications_update on notifications for update
using ( is_super_admin() )
with check ( is_super_admin() );

-- No insert/delete policy for regular roles on purpose -- only the
-- trigger function below (running with row_security off) writes rows.

create or replace function notify_client_closed()
returns trigger
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_actor_name text;
begin
  if NEW.project_status = 'closed' and OLD.project_status is distinct from 'closed' then
    select full_name into v_actor_name from users where id = auth.uid();
    insert into notifications (type, client_id, message)
    values (
      'client_closed',
      NEW.id,
      coalesce(v_actor_name, 'Someone') || ' closed ' || NEW.name || ' -- ready to be reassigned.'
    );
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_notify_client_closed on clients;
create trigger trg_notify_client_closed
after update of project_status on clients
for each row execute function notify_client_closed();
