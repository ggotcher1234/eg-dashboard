-- 197: Only Admins put an engagement On Hold, change a hold, or take one off
-- (Greg, 11/9/26: "lets just have the admins allowed to put an engagement on
-- hold"). The pages hide the controls from everyone else; this is the rule
-- underneath them. The nightly job (195) runs with no signed-in user and is
-- allowed through, so automatic returns and reminders keep working.

create or replace function public.enforce_admin_only_hold()
returns trigger
language plpgsql
as $$
begin
  if auth.uid() is null or is_super_admin() then
    return NEW;
  end if;
  if (NEW.project_status = 'on_hold' or OLD.project_status = 'on_hold')
     and NEW.project_status is distinct from OLD.project_status then
    raise exception 'Only an Admin can put an engagement On Hold or take it off hold.';
  end if;
  if NEW.hold_until is distinct from OLD.hold_until
     or NEW.hold_reason is distinct from OLD.hold_reason
     or NEW.hold_auto_return is distinct from OLD.hold_auto_return then
    raise exception 'Only an Admin can change an engagement''s hold.';
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_enforce_admin_only_hold on public.clients;
create trigger trg_enforce_admin_only_hold
  before update on public.clients
  for each row execute function public.enforce_admin_only_hold();
