-- 086_first_in_progress_at.sql
--
-- Depends on 051_engagement_status_tracking.sql (clients.status_since, the
-- track_status_since trigger).
--
-- Greg (8/28/26): the overdue clock should count from the day an engagement
-- was ORIGINALLY put In Progress, not reset every time the status is
-- toggled (e.g. a quick On Hold and back, or just clicking around while
-- testing). status_since still tracks "time in the current status run" and
-- is left alone -- first_in_progress_at is a separate, one-time-set
-- timestamp: it's stamped the first time an engagement ever enters In
-- Progress, and never touched again after that, even if the engagement
-- later moves to On Hold/Closed and comes back to In Progress.
--
-- Safe to re-run.

alter table clients add column if not exists first_in_progress_at timestamptz;

-- Backfill: for engagements already sitting In Progress today, we don't have
-- their true original entry date, so status_since (last change into the
-- current run) is the best available stand-in. Only backfills rows that
-- don't already have a value, so re-running this migration is harmless.
update clients
set first_in_progress_at = status_since
where project_status = 'in_progress'
  and first_in_progress_at is null;

create or replace function track_status_since()
returns trigger
language plpgsql
as $$
begin
  if NEW.project_status is distinct from OLD.project_status then
    NEW.status_since := now();
    if NEW.project_status is distinct from 'in_progress' then
      NEW.delay_reason := null;
    end if;
    if NEW.project_status = 'in_progress' and OLD.first_in_progress_at is null then
      NEW.first_in_progress_at := now();
    end if;
  end if;
  return NEW;
end;
$$;

-- Trigger definition (name/timing/columns) is unchanged from 051; the
-- function body above is what actually changed, and create or replace
-- already picked that up. Re-stating the trigger here anyway so this file
-- is a complete, standalone record of the current behavior.
drop trigger if exists trg_track_status_since on clients;
create trigger trg_track_status_since
before update of project_status on clients
for each row execute function track_status_since();
