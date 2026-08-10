-- 043_company_info_from_application.sql
--
-- Depends on 027_resource_vault_templates.sql (accept_client_application),
-- 042_user_avatar_upload.sql (latest tracked migration).
--
-- Greg: "the company information should grab whatever fields are available
-- from the application and fill them in on this form." Company Information
-- on client_profile.html (address, website_url, naics_codes, plus logo/
-- description/social links) lives on `clients`, but accept_client_application()
-- never copied any of it over from the intake application -- it only ever
-- copied organization_id/econ_dev_company_id/name/slug/budget_hours_available.
-- Every accepted client has started with a blank Company Information panel
-- even when the intake form had real data.
--
-- What actually has a clean match on client_applications:
--   address     (jsonb {street, city, state, postal, county}) -> clients.address (text)
--     -- flattened to "street, city state postal" (skips missing pieces).
--   website     (text) -> clients.website_url
--   naics_code  (text, singular) -> clients.naics_codes
-- What does NOT have a source on the application (so it's left alone,
-- nothing to copy): logo_url, description, and the five per-platform social
-- URLs (linkedin_url/facebook_url/instagram_url/twitter_url/youtube_url) --
-- the intake form only has one unstructured, newline-separated
-- `social_links` list, not split by platform, so guessing which line is
-- which platform risks writing a Twitter link into the LinkedIn field.
-- Those stay manual, same as logo/description already are.
--
-- Two parts:
--   1. accept_client_application() -- identical to 027's version except the
--      `insert into clients (...)` now also sets address/website_url/naics_codes
--      from the application, so every NEW acceptance carries this over
--      automatically.
--   2. A one-time backfill for clients that were already accepted before
--      this migration -- fills in address/website_url/naics_codes from
--      their original application ONLY where the client's own field is
--      still null, so nothing already filled in by hand gets overwritten.
--
-- Safe to re-run.

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
    address, website_url, naics_codes
  )
  values (
    v_app.organization_id, v_app.econ_dev_company_id, v_app.company_name, p_slug, p_budget_hours_available, auth.uid(),
    v_address, v_app.website, v_app.naics_code
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

  update client_applications
    set status = 'accepted', client_id = v_client_id, reviewed_by = auth.uid(), reviewed_at = now()
    where id = p_application_id;

  insert into audit_log (client_id, user_id, action, field, new_value)
  values (v_client_id, auth.uid(), 'client_accepted', 'status', 'active');

  return v_client_id;
end;
$$;

-- ----------------------------------------------------------------------
-- One-time backfill for clients accepted before this migration existed.
-- Only touches a field if it's currently null on the client AND the
-- application actually had a value -- never overwrites something Greg (or
-- the old intake data) already put there by hand.
-- ----------------------------------------------------------------------
update clients c
set
  address = coalesce(c.address, nullif(trim(both ', ' from concat_ws(', ',
    a.address->>'street',
    nullif(trim(concat_ws(' ', a.address->>'city', a.address->>'state', a.address->>'postal')), '')
  )), '')),
  website_url = coalesce(c.website_url, a.website),
  naics_codes = coalesce(c.naics_codes, a.naics_code)
from client_applications a
where a.client_id = c.id
  and (c.address is null or c.website_url is null or c.naics_codes is null);
