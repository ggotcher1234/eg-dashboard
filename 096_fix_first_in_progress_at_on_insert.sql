-- 096_fix_first_in_progress_at_on_insert.sql
--
-- Depends on 051_engagement_status_tracking.sql, 086_first_in_progress_at.sql,
-- 087_engagement_closed_at.sql (all three touch the same track_status_since
-- trigger/function).
--
-- Greg (8/30/26): "we fixed this before but the error has come back again"
-- -- Clippard Instrument Labs showed "In Progress for 2 days" when it's
-- actually been in progress much longer.
--
-- ROOT CAUSE: the trigger from 086/087 only fires BEFORE UPDATE OF
-- project_status -- it never runs on INSERT. Any client row that gets
-- created with project_status already set to 'in_progress' (a seeded/demo
-- client, or any insert path that doesn't go through the normal
-- Accepted -> In Progress toggle) is left with first_in_progress_at still
-- NULL. The next time that engagement's status is toggled away from In
-- Progress and back -- even just clicking around while testing the status
-- control -- the trigger sees OLD.first_in_progress_at IS NULL and
-- (correctly, per its own rule: "stamp it the first time we ever see this
-- column null going into in_progress") stamps it "now." That reads as if
-- the engagement just started, when really it's a data gap from creation,
-- not a genuine new start date.
--
-- FIX: extend the same trigger to also run BEFORE INSERT, so a client
-- inserted with project_status = 'in_progress' gets first_in_progress_at
-- stamped immediately at creation and can never be caught null later.
--
-- This migration only prevents the bug from happening again. It can't
-- recover the *true* original date for a client that already got
-- incorrectly reset (that data is gone) -- for those, use the new "Edit"
-- link next to the "In Progress for N days" box on the Engagement
-- Workspace page (Super Admin only, added in client_control_center.html
-- this same round) to set the correct date by hand.
--
-- Safe to re-run.

-- One-time catch-up for any row that's currently null (same idempotent
-- backfill 086 already ran -- re-stated here in case any row has slipped
-- through since, e.g. a client seeded directly via SQL after 086 ran).
update clients
set first_in_progress_at = status_since
where project_status = 'in_progress'
  and first_in_progress_at is null;

create or replace function track_status_since()
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
    if NEW.project_status = 'closed' then
      NEW.closed_at := now();
    end if;
  end if;
  return NEW;
end;
$$;

-- Now fires on INSERT too, not just UPDATE OF project_status.
drop trigger if exists trg_track_status_since on clients;
create trigger trg_track_status_since
before insert or update of project_status on clients
for each row execute function track_status_since();
