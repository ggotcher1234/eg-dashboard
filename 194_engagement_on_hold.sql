-- 194: On Hold engagements with an automatic return date.
--
-- Chris (11/9/26), on Condor Electronics (GRE): "this happens once in a while
-- around this time of year as people want to get in the queue but want to
-- close out their year before they jump into new business growth mode.
-- Return Jan 1." Greg: "maybe we have engagements, closed and on hold."
--
-- project_status = 'on_hold' parks an engagement: it leaves the In Progress
-- list, can't go Overdue, and comes back on its own on hold_until.
-- Coming back off hold restarts the 60-day clock (first_in_progress_at),
-- because the work hasn't started yet -- otherwise Condor would return on
-- Jan 1 already 53 days into its 60.

alter table public.clients add column if not exists hold_until date;

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
    -- 194: back from On Hold = a fresh start; the return date is spent.
    if NEW.project_status = 'in_progress' and OLD.project_status = 'on_hold' then
      NEW.first_in_progress_at := now();
      NEW.hold_until := null;
    end if;
    if NEW.project_status = 'closed' then
      NEW.closed_at := now();
      NEW.hold_until := null;
    end if;
  end if;
  return NEW;
end;
$$;

-- Daily release: anything whose return date has arrived (Eastern, same
-- calendar the month-end close rule uses) goes back to In Progress.
create or replace function public.release_held_engagements()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  update public.clients
     set project_status = 'in_progress'
   where project_status = 'on_hold'
     and hold_until is not null
     and hold_until <= (now() at time zone 'America/New_York')::date;
  get diagnostics n = row_count;
  return n;
end;
$$;

revoke all on function public.release_held_engagements() from public, anon, authenticated;

create extension if not exists pg_cron;

-- 06:05 UTC = just after 1 AM Eastern, so a Jan 1 return is back before
-- anyone opens the dashboard that morning.
select cron.unschedule(jobid) from cron.job where jobname = 'release-held-engagements';
select cron.schedule('release-held-engagements', '5 6 * * *', $$select public.release_held_engagements();$$);
