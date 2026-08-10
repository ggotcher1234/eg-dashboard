-- 044_relink_user_account.sql
--
-- Greg: got locked out, deleted his Supabase Auth user and recreated it
-- (typo'd the email the first try) to work around a broken password-reset
-- flow. That left his real staff profile row (`users`, holding role,
-- specialty, client assignments, everything) still pointed at the OLD
-- Auth UID -- the new login has no matching profile ("Signed in, but no
-- matching staff profile was found"). His question: "this is bound to
-- come up from time to time with other consultants. is there a way around
-- having to do this every time." Yes -- this migration is that way.
--
-- `users.id` is meant to always equal the corresponding auth.users.id
-- (auth.uid()). Whenever an account gets deleted & recreated in Supabase
-- Auth (locked out, name typo, whatever), it gets a brand new UID, and the
-- old `users` row -- plus every foreign key across the app that points at
-- it -- goes stale. Previously that meant asking me to hand-write a
-- one-off migration each time. relink_user_account() turns that into a
-- Super-Admin self-service action: pass the person's email and their new
-- Auth UID, and it repoints the profile row and every table that
-- references it, in one transaction.
--
-- Deliberately does NOT rely on `ON UPDATE CASCADE` on the existing
-- foreign keys -- most of those FKs were set up outside this repo's
-- tracked migrations (before 017), so their exact constraint definitions
-- aren't something I can safely alter blindly, and a plain UPDATE of
-- users.id in place doesn't work either way (Postgres checks each FK
-- immediately: updating the parent id first fails because old rows still
-- reference the old id, updating children first fails because the new id
-- doesn't exist as a parent yet). Instead this clones the profile row
-- under the new id (via to_jsonb/jsonb_populate_record, so it copies
-- every column generically -- nothing to keep in sync by hand if `users`
-- gains columns later), repoints every referencing row to that new row,
-- then deletes the old row now that nothing references it. If a
-- referencing table gets missed here in the future, the final DELETE
-- fails loudly with a foreign key violation (safe failure -- transaction
-- rolls back, nothing corrupted) rather than silently leaving orphaned
-- data.
--
-- Known tables with a column that holds a users.id value, per a full
-- repo grep (migrations + every .html file's Supabase queries):
--   client_assignments.user_id, audit_log.user_id, clients.created_by,
--   client_applications.reviewed_by, client_applications.submitted_by,
--   documents.uploaded_by, time_entries.consultant_id, notifications.read_by
--
-- Safe to re-run.

create or replace function relink_user_account(p_email text, p_new_auth_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_id uuid;
  v_row    jsonb;
begin
  if not is_super_admin() then
    raise exception 'Only a Super Admin can relink a login (Section 5.1)';
  end if;

  select id into v_old_id from users where lower(email) = lower(trim(p_email));
  if not found then
    raise exception 'No staff profile found for email %', p_email;
  end if;

  if v_old_id = p_new_auth_id then
    return v_old_id; -- already linked correctly, nothing to do
  end if;

  if exists (select 1 from users where id = p_new_auth_id) then
    raise exception 'Another staff profile already uses that login ID';
  end if;

  -- `users.id` is a foreign key TARGET for client_assignments.user_id and
  -- notifications.read_by (both `references users(id)`), so it can't just
  -- be UPDATEd in place -- the new id has to exist as a valid parent row
  -- before anything can point at it, but it also can't be inserted until
  -- we know every column to copy. to_jsonb/jsonb_populate_record captures
  -- and replays the ENTIRE row generically, whatever columns `users` has
  -- today or gains later (title, avatar_url, etc.) -- no hardcoded column
  -- list to keep in sync by hand.
  select to_jsonb(u) into v_row from users u where u.id = v_old_id;
  v_row := jsonb_set(v_row, '{id}', to_jsonb(p_new_auth_id::text));
  insert into users select * from jsonb_populate_record(null::users, v_row);

  update client_assignments      set user_id      = p_new_auth_id where user_id      = v_old_id;
  update audit_log                set user_id      = p_new_auth_id where user_id      = v_old_id;
  update clients                  set created_by   = p_new_auth_id where created_by   = v_old_id;
  update client_applications      set reviewed_by  = p_new_auth_id where reviewed_by  = v_old_id;
  update client_applications      set submitted_by = p_new_auth_id where submitted_by = v_old_id;
  update documents                set uploaded_by  = p_new_auth_id where uploaded_by  = v_old_id;
  update time_entries             set consultant_id= p_new_auth_id where consultant_id= v_old_id;
  update notifications            set read_by      = p_new_auth_id where read_by      = v_old_id;

  -- Safe now -- nothing references v_old_id anymore, so this delete
  -- succeeds without needing ON UPDATE CASCADE on any constraint.
  delete from users where id = v_old_id;

  return p_new_auth_id;
end;
$$;

grant execute on function relink_user_account(text, uuid) to authenticated;
