-- 195: On Hold for any reason -- illness, a client asking to wait -- with a
-- reminder to re-engage.
--
-- Greg (11/9/26): "sometimes engagements go on hold due to illness or other
-- factors so we just need a way to move them, track them and be reminded to
-- re-engage."
--
-- 194 gave every hold a date that automatically put the engagement back In
-- Progress. That fits "start Jan 1", not "owner is out sick": there the date
-- is when to check in, and nobody wants the 60-day clock restarting on its own.
-- So each hold now says which it is:
--   hold_auto_return = true   on hold_until it goes back In Progress (194)
--   hold_auto_return = false  on hold_until it STAYS On Hold and the Team
--                             Lead + Admins get a bell reminder to check in
-- hold_reason says why, for the On Hold list.
-- hold_reminded_on stops the same reminder going out every night; moving the
-- check-in date later arms it again.

alter table public.clients
  add column if not exists hold_reason text,
  add column if not exists hold_auto_return boolean not null default true,
  add column if not exists hold_reminded_on date;

-- Back In Progress or Closed: the hold's details are spent.
create or replace function public.track_status_since()
returns trigger
language plpgsql
as $$
begin
  if TG_OP = 'INSERT' then
    if NEW.project_status = 'in_progress' and NEW.first_in_progress_at is null then
      NEW.first_in_progress_at := coalesce(NEW.status_since, now());
    end if;
    return NEW;
  end if;

  if NEW.project_status is distinct from OLD.project_status then
    NEW.status_since := now();
    if NEW.project_status is distinct from 'in_progress' then
      NEW.delay_reason := null;
    end if;
    if NEW.project_status = 'in_progress' and OLD.first_in_progress_at is null then
      NEW.first_in_progress_at := now();
    end if;
    if NEW.project_status = 'in_progress' and OLD.project_status = 'on_hold' then
      NEW.first_in_progress_at := now();
    end if;
    if NEW.project_status = 'closed' then
      NEW.closed_at := now();
    end if;
    if NEW.project_status is distinct from 'on_hold' then
      NEW.hold_until := null;
      NEW.hold_reason := null;
      NEW.hold_auto_return := true;
      NEW.hold_reminded_on := null;
    end if;
  end if;
  return NEW;
end;
$$;

-- Bell notification to the engagement's Team Lead(s) and every Super Admin.
create or replace function public.notify_hold_event(p_client_id uuid, p_type text, p_message text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into notifications (type, client_id, message)
  values (p_type, p_client_id, p_message)
  returning id into v_id;

  insert into notification_recipients (notification_id, user_id)
  select v_id, u.id from users u where u.role = 'super_admin'
  union
  select v_id, a.user_id from client_assignments a
   where a.client_id = p_client_id and a.is_team_lead and a.user_id is not null
  on conflict (notification_id, user_id) do nothing;
end;
$$;

revoke all on function public.notify_hold_event(uuid, text, text) from public, anon, authenticated;

-- The nightly job (cron 'release-held-engagements', from 194) now does both.
create or replace function public.release_held_engagements()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'America/New_York')::date;
  r record;
  n integer := 0;
begin
  -- Automatic returns.
  for r in
    select id, name from clients
     where project_status = 'on_hold' and hold_auto_return
       and hold_until is not null and hold_until <= v_today
  loop
    update clients set project_status = 'in_progress' where id = r.id;
    perform notify_hold_event(r.id, 'hold_returned',
      r.name || ' is back In Progress after being On Hold. Time to re-engage.');
    n := n + 1;
  end loop;

  -- Check-in reminders; the engagement stays On Hold.
  for r in
    select id, name, hold_reason, status_since from clients
     where project_status = 'on_hold' and not hold_auto_return
       and hold_until is not null and hold_until <= v_today
       and (hold_reminded_on is null or hold_reminded_on < hold_until)
  loop
    perform notify_hold_event(r.id, 'hold_check_in',
      'Check in on ' || r.name || ' -- On Hold since '
      || to_char(r.status_since at time zone 'America/New_York', 'FMMon FMDD')
      || coalesce(' (' || nullif(trim(r.hold_reason), '') || ')', '')
      || '. Bring it back In Progress or set a new check-in date.');
    update clients set hold_reminded_on = v_today where id = r.id;
    n := n + 1;
  end loop;

  return n;
end;
$$;

revoke all on function public.release_held_engagements() from public, anon, authenticated;
