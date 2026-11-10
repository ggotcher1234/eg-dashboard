-- 196: Admins get a bell notification when an engagement goes On Hold or
-- comes off hold (Greg, 11/9/26). Same shape as notify_client_closed (023).
--
-- The person who made the change isn't notified about their own action.
-- An automatic return is skipped here: the nightly job (195) already tells
-- the Admins and the Team Lead, and a second bell for the same event is noise.
-- That job runs with no signed-in user, which is how it's told apart.

create or replace function public.notify_hold_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_actor_name text;
  v_msg text;
  v_id uuid;
  v_when text;
begin
  if NEW.project_status is not distinct from OLD.project_status then
    return NEW;
  end if;

  select full_name into v_actor_name from users where id = v_actor;

  if NEW.project_status = 'on_hold' then
    v_when := case when NEW.hold_until is null then ''
                   when NEW.hold_auto_return then ', back In Progress ' || to_char(NEW.hold_until, 'FMMon FMDD, YYYY')
                   else ', check in ' || to_char(NEW.hold_until, 'FMMon FMDD, YYYY') end;
    v_msg := coalesce(v_actor_name, 'Someone') || ' put ' || NEW.name || ' On Hold' || v_when
             || coalesce(' -- ' || nullif(trim(NEW.hold_reason), ''), '') || '.';
  elsif OLD.project_status = 'on_hold' then
    if v_actor is null then
      return NEW;
    end if;
    v_msg := coalesce(v_actor_name, 'Someone') || ' took ' || NEW.name || ' off hold -- now '
             || case NEW.project_status::text when 'in_progress' then 'In Progress' when 'closed' then 'Closed' else NEW.project_status::text end
             || '.';
  else
    return NEW;
  end if;

  insert into notifications (type, client_id, message)
  values (case when NEW.project_status = 'on_hold' then 'hold_started' else 'hold_ended' end, NEW.id, v_msg)
  returning id into v_id;

  insert into notification_recipients (notification_id, user_id)
  select v_id, u.id from users u
   where u.role = 'super_admin' and u.id is distinct from v_actor
  on conflict (notification_id, user_id) do nothing;

  return NEW;
end;
$$;

drop trigger if exists trg_notify_hold_status_change on public.clients;
create trigger trg_notify_hold_status_change
  after update of project_status on public.clients
  for each row execute function public.notify_hold_status_change();
