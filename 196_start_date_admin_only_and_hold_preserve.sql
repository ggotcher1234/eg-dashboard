-- 196: the engagement start date becomes an Admin-only, durable fact.
--
-- Greg (13/11/26), on giving Rita a way to correct the Podio imports.
--
-- ONE: clients_update lets a Team Lead write any column on their own
-- engagement, first_in_progress_at included -- the number their own overdue
-- clock is measured from. Hiding a button changes nothing; the API is still
-- open. The column joins the two fields this trigger already reserves.
--
-- TWO: returning from On Hold restamped first_in_progress_at to now(),
-- wiping any corrected date the moment an engagement resumed.
--
-- See 197, which adds the backend carve-out this version was missing.
create or replace function public.enforce_super_admin_client_fields()
returns trigger
language plpgsql
as $function$
begin
  if TG_OP = 'INSERT' and not is_super_admin() then
    raise exception 'Only a Super Admin can create a new client (Create New EG Client, Section 4.1)';
  end if;

  if TG_OP = 'UPDATE'
     and NEW.econ_dev_company_id is distinct from OLD.econ_dev_company_id
     and not is_super_admin() then
    raise exception 'Only a Super Admin can change a client''s Econ Dev company (Assign Econ-Dev, Section 4.1)';
  end if;

  if TG_OP = 'UPDATE'
     and NEW.budget_hours_available is distinct from OLD.budget_hours_available
     and not is_super_admin() then
    raise exception 'Only a Super Admin can change a client''s Budget Hours Available (Section 5.3)';
  end if;

  if TG_OP = 'UPDATE'
     and NEW.first_in_progress_at is distinct from OLD.first_in_progress_at
     and not is_super_admin() then
    raise exception 'Only a Super Admin can change an engagement''s start date';
  end if;

  return NEW;
end;
$function$;

create or replace function public.track_status_since()
returns trigger
language plpgsql
as $function$
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
    -- Stamped once, on the first move into In Progress, and never again.
    if NEW.project_status = 'in_progress' and OLD.first_in_progress_at is null then
      NEW.first_in_progress_at := now();
    end if;
    -- The on_hold -> in_progress restamp was here. Removed in 196: it wiped
    -- a corrected start date whenever an engagement resumed. status_since
    -- still moves on every status change, so that is the column to read
    -- when a clock should exclude time spent on hold.
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
$function$;
