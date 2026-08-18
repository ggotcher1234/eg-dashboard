-- 051_engagement_status_tracking.sql
--
-- Depends on 001_foundation_schema.sql (clients, project_status_type).
--
-- Greg (8/18/26): wants overdue engagements flagged -- usually because a
-- closing call can't get scheduled, but sometimes for other reasons -- with
-- a place to record *why* so he doesn't have to ask and the team doesn't
-- have to re-explain it every time.
--
-- status_since: the timestamp project_status last actually changed. Kept
-- current by the trigger below (BEFORE UPDATE, fires only when
-- project_status itself changes -- an unrelated field edit, e.g. fixing a
-- typo in the client name, does NOT reset the clock). The app uses this to
-- show a green/yellow/red indicator based on days spent in the current
-- status.
--
-- delay_reason: a short freeform note ("waiting on closing call",
-- "client unresponsive", etc.) a Team Lead or Admin can attach to an
-- engagement that's dragging. Cleared automatically the moment the status
-- moves off In Progress, so a stale reason doesn't linger and mislead
-- later -- if the same client re-enters In Progress down the road, it
-- starts with a clean slate.
--
-- Safe to re-run.

alter table clients add column if not exists status_since timestamptz not null default now();
alter table clients add column if not exists delay_reason text;

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
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_track_status_since on clients;
create trigger trg_track_status_since
before update of project_status on clients
for each row execute function track_status_since();
