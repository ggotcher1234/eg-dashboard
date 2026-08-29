-- 091_close_engagement_on_evaluation.sql
--
-- Depends on 090_next_step_auto_source.sql (sync_evaluation_next_step(),
-- the Close-Out Survey auto-complete trigger on client_evaluation_responses)
-- and 051_status_since.sql / 086_first_in_progress_at.sql /
-- 087_engagement_closed_at.sql (clients.project_status, the track_status_
-- since() trigger that stamps status_since/closed_at on any project_status
-- change -- already fires no matter who or what changes the column, so
-- nothing about it needs to change here).
--
-- Greg (8/29/26): "when this happens, automatically move the status of the
-- engagement to closed." Extends the same trigger 090 added -- the instant
-- a client submits their Close-Out Survey, in addition to auto-checking
-- that Next Step, this now also sets clients.project_status = 'closed' for
-- that engagement. That column change flows straight into the existing
-- track_status_since() trigger, which stamps closed_at the same way it
-- already does for a Team Lead manually closing an engagement by hand --
-- no separate closed_at logic needed here.
--
-- Deliberately NOT backfilled: any engagement that already had a submitted
-- survey before this migration but is still open is left exactly as it is.
-- Auto-closing a live engagement retroactively, with no one reviewing which
-- ones would be affected, is a bigger and more consequential action than
-- auto-checking a box -- only NEW submissions from here on trigger a close.
-- If you want existing already-submitted-but-open engagements swept up too,
-- say so and that's a one-line follow-up query, not a new migration.
--
-- Safe to re-run.

create or replace function sync_evaluation_next_step()
returns trigger
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
begin
  update client_next_steps
  set completed = true,
      notes = coalesce(
        nullif(trim(notes), ''),
        'Auto-completed -- client submitted the Close-Out Survey on ' || to_char(NEW.submitted_at, 'FMMM/DD/YYYY')
      )
  where client_id = NEW.client_id
    and auto_source = 'evaluation_submitted';

  update clients
  set project_status = 'closed'
  where id = NEW.client_id
    and project_status is distinct from 'closed';

  return NEW;
end;
$$;
