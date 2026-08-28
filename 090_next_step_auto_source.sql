-- 090_next_step_auto_source.sql
--
-- Depends on 019_client_profile_content.sql (client_next_steps),
-- 060_accept_application_contacts.sql (accept_client_application, the
-- current default Next Steps seed), 078_evaluation_responses.sql
-- (client_evaluation_responses -- the Close-Out Survey submission data).
--
-- Chris (8/28/26, on today's call): Team Leads won't reliably check off the
-- 6 default Next Steps by hand -- if a step can log itself the way the
-- Close-Out Survey link already does, it should. First target: it turns out
-- the Close-Out Survey step ISN'T actually wired to auto-complete today --
-- client_evaluation_responses holds the real submission, but nothing ever
-- set the matching client_next_steps row's `completed` flag. A Team Lead
-- still had to go check that box by hand even after a client submitted the
-- survey. This migration closes that gap and builds the reusable mechanism
-- the harder Next Steps can lean on later.
--
-- This adds a generic `auto_source` tag to client_next_steps (null = manual,
-- unchanged behavior for every custom row a Team Lead types in by hand) and
-- wires the one known value so far, 'evaluation_submitted', to a trigger on
-- client_evaluation_responses: the instant a response is submitted, the
-- matching client's Close-Out Survey row flips to completed automatically.
-- Tagging by auto_source (set once, at row-creation time) instead of
-- matching on the description text means a Team Lead can still freely
-- rename that row's Task text without ever breaking the automation.
--
-- Four parts:
--   1. client_next_steps.auto_source text, nullable, default null.
--   2. Backfill: tag existing "Close-Out Survey" default rows (matched by
--      the exact description + notes text accept_client_application() has
--      always seeded -- so a custom row a Team Lead happened to also title
--      "Close-Out Survey" but wrote their own note on isn't touched).
--   3. accept_client_application() re-defined, otherwise identical to
--      060's version, so every NEW engagement's Close-Out Survey row is
--      tagged automatically going forward.
--   4. sync_evaluation_next_step() trigger on client_evaluation_responses:
--      after each insert, marks that client's auto_source =
--      'evaluation_submitted' row(s) completed, filling in Notes with the
--      submission date only if Notes is currently blank (never overwrites
--      something a Team Lead already typed there). A one-time backfill
--      below also runs this once for engagements that already have a
--      submitted survey, so existing clients don't have to wait for a
--      second submission to catch up.
--
-- Safe to re-run.

-- ---------- 1. auto_source column ----------
alter table client_next_steps add column if not exists auto_source text;

comment on column client_next_steps.auto_source is
  'Set once at row-creation time to tag a step as system-driven instead of manually checked off. Null = manual (default for every custom row). Known values: evaluation_submitted (Close-Out Survey, wired 8/28/26 -- see 090_next_step_auto_source.sql).';

-- ---------- 2. Backfill: tag existing default Close-Out Survey rows ----------
update client_next_steps
set auto_source = 'evaluation_submitted'
where auto_source is null
  and description = 'Close-Out Survey'
  and notes = 'How did we do?';

-- ---------- 3. accept_client_application() -- tag new engagements' default row ----------
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
    (v_client_id, 'Close-Out Survey', 'How did we do?', false, 6, 'evaluation_submitted');

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

-- ---------- 4. Auto-complete Close-Out Survey Next Step on submission ----------
create or replace function sync_evaluation_next_step()
returns trigger
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
begin
  update client_next_steps
  set completed = true,
      notes = coalesce(
        nullif(trim(notes), ''),
        'Auto-completed -- client submitted the Close-Out Survey on ' || to_char(NEW.submitted_at, 'FMMM/DD/YYYY')
      )
  where client_id = NEW.client_id
    and auto_source = 'evaluation_submitted';
  return NEW;
end;
$$;

drop trigger if exists trg_sync_evaluation_next_step on client_evaluation_responses;
create trigger trg_sync_evaluation_next_step
after insert on client_evaluation_responses
for each row execute function sync_evaluation_next_step();

-- One-time backfill: any client that already has a submitted survey gets
-- their Close-Out Survey Next Step marked complete retroactively right now,
-- instead of waiting on a brand new submission to trigger it.
update client_next_steps n
set completed = true,
    notes = coalesce(
      nullif(trim(n.notes), ''),
      'Auto-completed -- client submitted the Close-Out Survey on ' || to_char(r.submitted_at, 'FMMM/DD/YYYY')
    )
from (
  select client_id, max(submitted_at) as submitted_at
  from client_evaluation_responses
  group by client_id
) r
where n.client_id = r.client_id
  and n.auto_source = 'evaluation_submitted';
