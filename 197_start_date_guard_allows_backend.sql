-- 197: 196's start-date guard also refused SQL run with no signed-in user.
--
-- is_super_admin() reads auth.uid(), so from the SQL console or a service
-- role it is false and the guard fired on maintenance updates -- the ones
-- that fix the imported dates in the first place. Caught by testing the
-- trigger rather than by Rita hitting it on Monday.
--
-- auth.uid() is null only when nobody is signed in: the SQL console, a
-- service-role job, a migration. Each already has full access to the table,
-- so skipping the check there removes no protection. A Team Lead always
-- carries a uid, which is the case this guards against; an anonymous caller
-- never reaches the trigger, because clients_update matches it no rows.
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
     and auth.uid() is not null
     and not is_super_admin() then
    raise exception 'Only a Super Admin can change an engagement''s start date';
  end if;

  return NEW;
end;
$function$;
