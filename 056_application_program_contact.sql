-- 056_application_program_contact.sql
--
-- Depends on 039_econ_dev_partner_contacts.sql, 040_client_team_partner_contacts.sql,
-- and 045_top_business_issues.sql (accept_client_application).
--
-- Greg (8/18/26): "let's add the program contact for the engagement to the
-- application too." The New Application wizard already picks the EG
-- Program (econ_dev_company_id); this adds a matching "who at that program
-- do we coordinate with" pick, sourced from the same
-- econ_dev_partner_contacts list client_profile.html's Team section already
-- offers post-acceptance (039/040/041).
--
-- Two parts:
--   1. client_applications gains program_contact_id, nullable FK to
--      econ_dev_partner_contacts. set null on delete (never block deleting a
--      partner contact just because an old application referenced them).
--   2. accept_client_application() -- identical to 045's version, except
--      that when the accepted application has a program_contact_id set, it
--      also inserts the matching client_team_partner_contacts row so that
--      contact shows up on the new client's Team list immediately, with no
--      manual re-selection step in client_profile.html.
--
-- Safe to re-run.

alter table client_applications
  add column if not exists program_contact_id uuid references econ_dev_partner_contacts(id) on delete set null;

-- ----------------------------------------------------------------------
-- accept_client_application()
-- ----------------------------------------------------------------------
drop function if exists accept_client_application(uuid, numeric, uuid, text, numeric, numeric);

create or replace function accept_client_application(
  p_application_id            uuid,
  p_budget_hours_available    numeric,
  p_team_lead_id               uuid,
  p_slug                       text,
  p_admin_hours                numeric default 2,
  p_qc_hours                   numeric default 3
) returns uuid
language plpgsql
security invoker
as $$
declare
  v_app       client_applications;
  v_client_id uuid;
  v_address   text;
begin
  if not is_super_admin() then
    raise exception 'Only a Super Admin can accept an application (Section 5.2)';
  end if;

  select * into v_app from client_applications
    where id = p_application_id and status = 'pending';
  if not found then
    raise exception 'Application not found or already processed';
  end if;

  v_address := nullif(trim(both ', ' from concat_ws(', ',
    v_app.address->>'street',
    nullif(trim(concat_ws(' ', v_app.address->>'city', v_app.address->>'state', v_app.address->>'postal')), '')
  )), '');

  insert into clients (
    organization_id, econ_dev_company_id, name, slug, budget_hours_available, created_by,
    address, website_url, naics_codes, top_business_issues
  )
  values (
    v_app.organization_id, v_app.econ_dev_company_id, v_app.company_name, p_slug, p_budget_hours_available, auth.uid(),
    v_address, v_app.website, v_app.naics_code, v_app.top_business_issues
  )
  returning id into v_client_id;

  insert into client_content (client_id) values (v_client_id);
  insert into client_share_links (client_id, subdomain) values (v_client_id, p_slug);

  insert into client_assignments (client_id, user_id, specialty_type, slot_number, hours_allotted, is_team_lead)
  values (v_client_id, p_team_lead_id, 'team_lead', 1, 0, true);

  insert into client_assignments (client_id, user_id, specialty_type, slot_number, hours_allotted, is_team_lead) values
    (v_client_id, null, 'market_research',   1, 0,            false),
    (v_client_id, null, 'digital_marketing', 1, 0,            false),
    (v_client_id, null, 'gis',               1, 0,            false),
    (v_client_id, null, 'watering_holes',    1, 0,            false),
    (v_client_id, null, 'admin',             1, p_admin_hours, false),
    (v_client_id, null, 'quality_control',   1, p_qc_hours,    false);

  insert into client_next_steps (client_id, description, notes, completed, sort_order) values
    (v_client_id, 'Send EG Invitation Email', null, false, 1),
    (v_client_id, 'Discovery Call', null, false, 2),
    (v_client_id, 'Controlling Document', 'Agree on documented research approach', false, 3),
    (v_client_id, 'Research Controlling Document', 'Assign EG team to research areas', false, 4),
    (v_client_id, 'Client Research Review Call', 'Zoom Call with Researchers', false, 5),
    (v_client_id, 'Close-Out Survey', 'How did we do?', false, 6);

  insert into client_resource_vault_items (client_id, template_id, sort_order)
  select v_client_id, rvt.id, rvt.sort_order
  from resource_vault_templates rvt
  where rvt.organization_id = v_app.organization_id
  order by rvt.sort_order;

  -- New in this migration: carry the application's chosen Program Contact
  -- straight onto the client's Team list, so it doesn't have to be
  -- re-picked from scratch in client_profile.html right after acceptance.
  if v_app.program_contact_id is not null then
    insert into client_team_partner_contacts (client_id, partner_contact_id)
    values (v_client_id, v_app.program_contact_id)
    on conflict (client_id, partner_contact_id) do nothing;
  end if;

  update client_applications
    set status = 'accepted', client_id = v_client_id, reviewed_by = auth.uid(), reviewed_at = now()
    where id = p_application_id;

  insert into audit_log (client_id, user_id, action, field, new_value)
  values (v_client_id, auth.uid(), 'client_accepted', 'status', 'active');

  return v_client_id;
end;
$$;
