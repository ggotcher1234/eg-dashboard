-- 087_engagement_closed_at.sql
--
-- Depends on 051_engagement_status_tracking.sql (clients.status_since, the
-- track_status_since trigger) and 086_first_in_progress_at.sql (same
-- trigger, extended once already).
--
-- Greg (8/28/26, per the platform review meeting): there's no timestamp
-- anywhere for "when did this engagement's project_status become Closed."
-- clients.date_closed is a different thing entirely -- it's stamped by
-- finalize_client() as part of the separate archive/finalize lifecycle
-- (clients.status: active/finalized/archived), not by project_status
-- moving to 'closed'. This adds a dedicated column for that, following the
-- same trigger pattern status_since/first_in_progress_at already use.
--
-- Unlike first_in_progress_at (stamped once, ever), closed_at is stamped
-- every time project_status transitions INTO 'closed' -- if an engagement
-- is reopened and closed again later, closed_at reflects the most recent
-- closure, which is what "when was this closed" should mean.
--
-- Safe to re-run.

alter table clients add column if not exists closed_at timestamptz;

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
    if NEW.project_status = 'closed' then
      NEW.closed_at := now();
    end if;
  end if;
  return NEW;
end;
$$;

-- Trigger definition (name/timing/columns) is unchanged from 051/086; the
-- function body above is what actually changed, and create or replace
-- already picked that up. Re-stating the trigger here anyway so this file
-- is a complete, standalone record of the current behavior.
drop trigger if exists trg_track_status_since on clients;
create trigger trg_track_status_since
before update of project_status on clients
for each row execute function track_status_since();

-- Backfill: for engagements already sitting Closed today, we don't have
-- their true closure date, so status_since (last change into the current
-- run, which for a currently-closed row IS the closure date) is the best
-- available stand-in. Only backfills rows that don't already have a
-- value, so re-running this migration is harmless.
update clients
set closed_at = status_since
where project_status = 'closed'
  and closed_at is null;
