-- 092_close_out_survey_default_text.sql
--
-- Depends on 090_next_step_auto_source.sql (auto_source tagging, the
-- current accept_client_application()) and 091_close_engagement_on_
-- evaluation.sql (the step now also closes the engagement, not just logs
-- feedback).
--
-- Greg (8/29/26): wants the Close-Out Survey step's default Task/Notes text
-- to read "Close-Out Survey Completed" / "Closes Engagement when client
-- submits" instead of "Close-Out Survey" / "How did we do?" -- clearer now
-- that this step both auto-completes AND closes the engagement, matching
-- text Greg already hand-typed onto one live client's row.
--
-- Two parts:
--   1. accept_client_application() re-defined with the new default text for
--      every NEW engagement going forward -- otherwise identical to 090's
--      version (auto_source tagging carries over unchanged).
--   2. Backfill: any EXISTING client_next_steps row still carrying the OLD
--      exact default text ("Close-Out Survey" / "How did we do?") gets
--      updated to the new wording. Matched by the exact old text, same
--      conservative guard 090 used for its own tagging backfill -- a row a
--      Team Lead already retyped in their own words (including the one
--      client Greg already hand-edited to this exact new text) is left
--      untouched either way.
--
-- Safe to re-run.

-- ---------- 1. accept_client_application() -- new default text going forward ----------
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

  insert into client_next_steps (client_id, description, notes, completed, sort_order, auto_source) values
    (v_client_id, 'Send EG Invitation Email', null, false, 1, null),
    (v_client_id, 'Discovery Call', null, false, 2, null),
    (v_client_id, 'Controlling Document', 'Agree on documented research approach', false, 3, null),
    (v_client_id, 'Research Controlling Document', 'Assign EG team to research areas', false, 4, null),
    (v_client_id, 'Client Research Review Call', 'Zoom Call with Researchers', false, 5, null),
    (v_client_id, 'Close-Out Survey Completed', 'Closes Engagement when client submits', false, 6, 'evaluation_submitted');

  insert into client_resource_vault_items (client_id, template_id, sort_order)
  select v_client_id, rvt.id, rvt.sort_order
  from resource_vault_templates rvt
  where rvt.organization_id = v_app.organization_id
  order by rvt.sort_order;

  -- Carry the application's chosen Program Contact straight onto the
  -- client's Team list (056), so it doesn't have to be re-picked from
  -- scratch in client_profile.html right after acceptance.
  if v_app.program_contact_id is not null then
    insert into client_team_partner_contacts (client_id, partner_contact_id)
    values (v_client_id, v_app.program_contact_id)
    on conflict (client_id, partner_contact_id) do nothing;
  end if;

  -- Carry the up-to-three Company Contacts collected on the application
  -- (Primary/Secondary/3rd) straight into client_contacts (060), so
  -- client_profile.html's "Company Contacts" step is pre-populated instead
  -- of starting empty. Each slot is skipped if its name was left blank.
  if nullif(trim(v_app.primary_officer_name), '') is not null then
    insert into client_contacts (client_id, name, title, email, phone, sort_order)
    values (v_client_id, v_app.primary_officer_name, v_app.primary_officer_title,
            v_app.primary_officer_email, v_app.primary_officer_phone, 1);
  end if;

  if nullif(trim(v_app.secondary_officer_name), '') is not null then
    insert into client_contacts (client_id, name, title, email, phone, sort_order)
    values (v_client_id, v_app.secondary_officer_name, v_app.secondary_officer_title,
            v_app.secondary_officer_email, v_app.secondary_officer_phone, 2);
  end if;

  if nullif(trim(v_app.tertiary_officer_name), '') is not null then
    insert into client_contacts (client_id, name, title, email, phone, sort_order)
    values (v_client_id, v_app.tertiary_officer_name, v_app.tertiary_officer_title,
            v_app.tertiary_officer_email, v_app.tertiary_officer_phone, 3);
  end if;

  update client_applications
    set status = 'accepted', client_id = v_client_id, reviewed_by = auth.uid(), reviewed_at = now()
    where id = p_application_id;

  insert into audit_log (client_id, user_id, action, field, new_value)
  values (v_client_id, auth.uid(), 'client_accepted', 'status', 'active');

  return v_client_id;
end;
$$;

-- ---------- 2. Backfill: rename existing default rows still using the old text ----------
update client_next_steps
set description = 'Close-Out Survey Completed',
    notes = 'Closes Engagement when client submits'
where auto_source = 'evaluation_submitted'
  and description = 'Close-Out Survey'
  and notes = 'How did we do?';
