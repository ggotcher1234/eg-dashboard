-- 171_admin_correct_time_entry.sql
--
-- Greg (10/16, from the call): "Admin will have administrative power to
-- override timestamps on spent hours to correct billing errors." Scope
-- settled the same day: the date AND the number of hours, with the
-- correction visible in the Billing History rather than silent.
--
-- This is the remaining half of punch list #301. The date half was settled
-- on 10/10 by removing the date picker (#110) -- an entry is stamped with
-- the day it was logged, so nobody can mis-date one going in. What stayed
-- broken is coming back out: an entry logged for the wrong number of hours,
-- or stamped into the wrong month because it was typed late, could not be
-- touched by anybody, so the month's invoice had to be reconciled by hand.
--
-- The database already allowed it -- the time_entries update policy has an
-- is_super_admin() branch -- there was simply no way to do it in the app,
-- and a raw update would leave no record of what changed. Hence an RPC
-- rather than a plain update from the page: the correction and its audit
-- row are written together or not at all.
--
-- WHAT IS REMEMBERED. original_entry_date and original_hours are written
-- ONCE, on the first correction, so a second correction still shows what
-- the specialist actually logged rather than what the last Admin typed.
-- corrected_at/corrected_by always move.
--
-- Deliberately NOT included: removing an entry. Greg chose date and hours
-- (10/16); a removal leaves no trace in a running total, and a duplicate
-- can be corrected to zero hours and explained in its note instead.
--
-- Safe to re-run.

alter table time_entries add column if not exists corrected_at        timestamptz;
alter table time_entries add column if not exists corrected_by        uuid references users(id);
alter table time_entries add column if not exists original_entry_date date;
alter table time_entries add column if not exists original_hours      numeric;

comment on column time_entries.original_entry_date is
  'The date the specialist actually logged against, kept from the first Admin correction onward. Null means never corrected.';

create or replace function admin_correct_time_entry(
  p_entry_id   uuid,
  p_entry_date date,
  p_hours      numeric,
  p_note       text default null
) returns time_entries
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_entry  time_entries;
  v_client uuid;
begin
  if not is_super_admin() then
    raise exception 'Only an Admin can correct a logged time entry.';
  end if;

  select * into v_entry from time_entries where id = p_entry_id;
  if not found then
    raise exception 'That time entry no longer exists.';
  end if;

  if p_hours is null or p_hours < 0 then
    raise exception 'Hours must be zero or more.';
  end if;
  if p_entry_date is null then
    raise exception 'An entry needs a date.';
  end if;
  -- A correction moves an entry to the month it belongs in, which is always
  -- now or earlier. A future date would bill work that has not happened.
  if p_entry_date > (current_timestamp at time zone 'America/New_York')::date then
    raise exception 'An entry cannot be dated in the future.';
  end if;

  -- Nothing actually changed -- say so rather than writing an audit row that
  -- records a correction that corrected nothing.
  if v_entry.entry_date = p_entry_date
     and v_entry.hours = p_hours
     and coalesce(nullif(trim(p_note), ''), '') is not distinct from coalesce(v_entry.note, '')
  then
    return v_entry;
  end if;

  update time_entries t
     set entry_date = p_entry_date,
         hours      = p_hours,
         note       = coalesce(nullif(trim(p_note), ''), t.note),
         -- Written once, so the specialist's own figures survive a second pass.
         original_entry_date = coalesce(t.original_entry_date, t.entry_date),
         original_hours      = coalesce(t.original_hours,      t.hours),
         corrected_at = now(),
         corrected_by = auth.uid()
   where t.id = p_entry_id
  returning * into v_entry;

  select c.client_id into v_client
    from client_assignments c where c.id = v_entry.assignment_id;

  insert into audit_log (client_id, user_id, action, field, old_value, new_value)
  values (
    v_client, auth.uid(), 'time_entry_corrected', 'entry_date + hours',
    v_entry.original_entry_date || ' / ' || v_entry.original_hours || ' hrs',
    v_entry.entry_date || ' / ' || v_entry.hours || ' hrs'
  );

  return v_entry;
end;
$$;

revoke all on function admin_correct_time_entry(uuid, date, numeric, text) from public;
grant execute on function admin_correct_time_entry(uuid, date, numeric, text) to authenticated;

notify pgrst, 'reload schema';
