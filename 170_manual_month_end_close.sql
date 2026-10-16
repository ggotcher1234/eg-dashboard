-- 170_manual_month_end_close.sql
--
-- Greg (10/16, from the call): "Engagements will no longer close
-- automatically upon evaluation submission; instead, a manual drop-dead
-- button will be used, restricted to the last day of the month... use the
-- existing Closed status button with a note that engagements need to be
-- closed on the last day of each month. If you need assistance contact
-- Rita. The rules are that clicking the close button gets an error message
-- unless it is the last day of the month."
--
-- WHY IT MATTERS. Closing an engagement locks its hours: the insert policy
-- on time_entries goes through client_hours_editable(), which is false for
-- a closed engagement. So the close date is a billing cut-off, not a
-- bookkeeping note. Until now a client submitting their evaluation closed
-- the engagement on the spot -- mid-month, with nobody choosing the moment
-- -- and the close-out call hours and final write-up were locked out
-- before they were logged. Month-end closing puts the cut-off on the same
-- boundary the invoices already use.
--
-- THREE PARTS.
--
-- 1. sync_evaluation_next_step() keeps auto-completing the Close-Out
--    Survey Next Step and no longer touches project_status. The engagement
--    stays open until somebody closes it.
--
-- 2. enforce_month_end_close() refuses any change TO 'closed' unless today
--    is the last day of the month. Enforced in the database rather than in
--    the page, so it holds on all three screens that carry the status
--    control -- the Control Center, the workspace and the application page
--    -- and cannot be stepped around.
--
--    Eastern time always (Greg's call, 10/16): one company calendar, so an
--    engagement closes on the same civil day whichever time zone the Team
--    Lead is in. current_date here would be UTC, which turns 8pm on the
--    31st in New York into the 1st -- the same slip fixed for logged hours
--    in October.
--
--    Admins are exempt, which is what "contact Rita" depends on: she needs
--    a way to actually close one off-cycle. is_super_admin() is false while
--    an Admin is using the role-view switcher, so an Admin viewing as a
--    Team Lead gets the Team Lead's rule -- deliberate.
--
-- 3. Nothing re-opens anything. Engagements already closed stay closed,
--    including ones the old trigger closed mid-month.
--
-- Uses CREATE OR REPLACE TRIGGER (Postgres 14+) rather than drop-and-create,
-- so re-running this is safe and leaves no window with no trigger on the
-- table.

create or replace function sync_evaluation_next_step()
returns trigger
language plpgsql
security definer
set search_path to 'public'
set row_security to 'off'
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

  -- The auto-close that used to sit here is gone (10/16). An engagement is
  -- closed by hand on the last day of the month; see enforce_month_end_close().

  return NEW;
end;
$$;

-- The last day of the current month, Eastern. One place, so the trigger and
-- anything that wants to show the date agree.
create or replace function month_end_eastern()
returns date
language sql
stable
set search_path to 'public'
as $$
  select (date_trunc('month', (current_timestamp at time zone 'America/New_York')::date)
          + interval '1 month' - interval '1 day')::date;
$$;

create or replace function is_month_end_eastern()
returns boolean
language sql
stable
set search_path to 'public'
as $$
  select (current_timestamp at time zone 'America/New_York')::date = month_end_eastern();
$$;

create or replace function enforce_month_end_close()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_last date := month_end_eastern();
begin
  if NEW.project_status = 'closed'
     and OLD.project_status is distinct from 'closed'
     and not is_super_admin()
     and not is_month_end_eastern()
  then
    raise exception
      'Engagements are closed on the last day of the month. The next one is %. If you need assistance, contact Rita.',
      to_char(v_last, 'FMDay, FMMonth FMDD');
  end if;
  return NEW;
end;
$$;

create or replace trigger trg_enforce_month_end_close
  before update on clients
  for each row
  execute function enforce_month_end_close();

-- Check: today's Eastern date, the month end it is measured against, and
-- whether a Team Lead could close an engagement right now.
select (current_timestamp at time zone 'America/New_York')::date as today_eastern,
       month_end_eastern()                                       as closes_on,
       is_month_end_eastern()                                    as team_lead_may_close_today;
