-- 068_public_program_contacts.sql
--
-- Greg (8/21/26): "add a dropdown field for Program Contact" on the public
-- application page. The CEO filling this out has no login, so -- same
-- reasoning as get_public_program_by_code() in 066 -- this is a narrow
-- security-definer RPC rather than a blanket anon SELECT policy on
-- econ_dev_partner_contacts (which also holds each contact's email/phone).
-- It only ever returns id/name/title for ONE program's contacts, matching
-- exactly what the internal wizard's own Program Contact dropdown shows
-- (client_applications.html's refreshProgramContactOptions()) -- no email
-- or phone leaves the database for this.
--
-- Depends on 066_public_program_applications.sql.
--
-- Safe to re-run.

create or replace function get_public_program_contacts(p_program_id uuid)
returns table (id uuid, name text, title text)
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select c.id, c.name, c.title
  from econ_dev_partner_contacts c
  where c.partner_id = p_program_id and c.active = true
  order by c.sort_order, c.created_at;
$$;

grant execute on function get_public_program_contacts(uuid) to anon, authenticated;
