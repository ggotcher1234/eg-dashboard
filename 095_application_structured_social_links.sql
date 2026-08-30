-- 095_application_structured_social_links.sql
--
-- Greg (8/29/26), correcting course on the social-links change in 094:
-- "i want the client to give them to us on the application. then we don't
-- have to guess what they are and waste time finding them." So social
-- links stay OUT of the internal wizard's from-scratch manual-entry feel
-- (that part of 094 was right), but the data itself needs to be captured
-- at application time (mainly via the public application form the client
-- fills out) and carried straight onto the client's Company page at
-- Accept -- with zero re-typing or re-Googling by EG staff.
--
-- The old `social_links text[]` column (pre-dates this repo's numbered
-- migrations) can't support that: it's an unlabeled blob of URLs, so there
-- was no safe way to know which URL was LinkedIn vs Facebook vs whatever
-- when bridging into clients' per-platform columns. This adds one
-- structured column per platform on client_applications, matching the 6
-- fields on clients (019_client_profile_content.sql + 094's other_social_
-- url) exactly -- so the bridge in accept_client_application() below is a
-- straight 1:1 copy, no parsing/guessing involved.
--
-- The old `social_links` column and its data are left untouched -- already-
-- submitted historical applications keep showing under that column in the
-- read-only Application detail view; only new applications populate the
-- 6 new columns.
--
-- Safe to re-run.

alter table client_applications add column if not exists social_facebook_url  text;
alter table client_applications add column if not exists social_linkedin_url  text;
alter table client_applications add column if not exists social_twitter_url   text;
alter table client_applications add column if not exists social_instagram_url text;
alter table client_applications add column if not exists social_youtube_url   text;
alter table client_applications add column if not exists social_other_url     text;

-- ---------- accept_client_application() -- bridge the 6 columns onto clients ----------
-- Identical to 092's version except the `insert into clients (...)` now
-- also carries the 6 social columns straight across, same pattern already
-- used for website_url/naics_codes/top_business_issues.
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
    address, website_url, naics_codes, top_business_issues,
    facebook_url, linkedin_url, twitter_url, instagram_url, youtube_url, other_social_url
  )
  values (
    v_app.organization_id, v_app.econ_dev_company_id, v_app.company_name, p_slug, p_budget_hours_available, auth.uid(),
    v_address, v_app.website, v_app.naics_code, v_app.top_business_issues,
    v_app.social_facebook_url, v_app.social_linkedin_url, v_app.social_twitter_url,
    v_app.social_instagram_url, v_app.social_youtube_url, v_app.social_other_url
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
