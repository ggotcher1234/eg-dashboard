-- 060_accept_application_contacts.sql
--
-- Depends on 019_client_profile_content.sql (client_contacts) and
-- 056_application_program_contact.sql (accept_client_application).
--
-- Greg (8/19/26), looking at client_profile.html's Dashboard Wizard "Contacts"
-- step for a freshly-accepted engagement: "the company contacts should
-- autofil from the application." The New Application wizard's own Contacts
-- step (client_applications.html step 3 of 5) already collects up to three
-- company contacts -- Primary/Secondary/3rd, each with name/title/email/phone
-- (stored on client_applications as primary_officer_*, secondary_officer_*,
-- tertiary_officer_* columns) -- but accept_client_application() never copied
-- any of it into client_contacts, so the Contacts step always started as
-- "Nothing added yet." even though the info was typed in at application time.
--
-- accept_client_application() is otherwise identical to 056's version; the
-- only change is three new conditional inserts into client_contacts (one per
-- officer slot, skipped when that slot's name was left blank), right after
-- the existing Team-list/program-contact carry-over.
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

  -- Carry the application's chosen Program Contact straight onto the
  -- client's Team list (056), so it doesn't have to be re-picked from
  -- scratch in client_profile.html right after acceptance.
  if v_app.program_contact_id is not null then
    insert into client_team_partner_contacts (client_id, partner_contact_id)
    values (v_client_id, v_app.program_contact_id)
    on conflict (client_id, partner_contact_id) do nothing;
  end if;

  -- New in this migration: carry the up-to-three Company Contacts collected
  -- on the application (Primary/Secondary/3rd) straight into client_contacts,
  -- so client_profile.html's "Company Contacts" step is pre-populated
  -- instead of starting empty. Each slot is skipped if its name was left
  -- blank on the application.
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

-- ----------------------------------------------------------------------
-- One-time backfill: engagements accepted BEFORE this migration (e.g.
-- Extremis Systems) got no client_contacts rows, since the old
-- accept_client_application() never wrote them. This copies the same
-- officer_* fields over for any already-accepted application whose client
-- still has zero rows in client_contacts. Safe to re-run -- the "0 existing
-- contacts" guard means it only ever fires once per client.
-- ----------------------------------------------------------------------
insert into client_contacts (client_id, name, title, email, phone, sort_order)
select a.client_id, a.primary_officer_name, a.primary_officer_title,
       a.primary_officer_email, a.primary_officer_phone, 1
from client_applications a
where a.status = 'accepted'
  and a.client_id is not null
  and nullif(trim(a.primary_officer_name), '') is not null
  and not exists (select 1 from client_contacts c where c.client_id = a.client_id);

insert into client_contacts (client_id, name, title, email, phone, sort_order)
select a.client_id, a.secondary_officer_name, a.secondary_officer_title,
       a.secondary_officer_email, a.secondary_officer_phone, 2
from client_applications a
where a.status = 'accepted'
  and a.client_id is not null
  and nullif(trim(a.secondary_officer_name), '') is not null
  and not exists (
    select 1 from client_contacts c
    where c.client_id = a.client_id and c.sort_order = 2
  );

insert into client_contacts (client_id, name, title, email, phone, sort_order)
select a.client_id, a.tertiary_officer_name, a.tertiary_officer_title,
       a.tertiary_officer_email, a.tertiary_officer_phone, 3
from client_applications a
where a.status = 'accepted'
  and a.client_id is not null
  and nullif(trim(a.tertiary_officer_name), '') is not null
  and not exists (
    select 1 from client_contacts c
    where c.client_id = a.client_id and c.sort_order = 3
  );
