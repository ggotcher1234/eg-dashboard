-- 027_resource_vault_templates.sql
--
-- Depends on 025_next_steps_notes_and_defaults.sql.
--
-- Greg: "these are the same resources for every client every time... I
-- don't want to use my dropbox for the URLs, I want to be able to upload a
-- file for each document listed." Confirmed via follow-up: shared master
-- files (Recommended) -- upload each of the 8 standard files ONCE, every
-- client's Resource Vault shows those same files, and updating the master
-- file updates it everywhere.
--
-- New model:
--   resource_vault_templates  -- org-wide, Super-Admin-managed master list
--                                 (title, description, uploaded file).
--   client_resource_vault_items gains a nullable template_id. A row with
--     template_id set is a "linked" row -- its title/description/file
--     always resolve from the template, live, everywhere it's read. A row
--     with template_id null is a fully custom, client-specific resource
--     (the existing behavior), which can now also carry an uploaded file
--     (storage_path) instead of typing a URL.
--
-- Every client accepted from now on automatically gets all 8 templates
-- linked in (same mechanism as accept_client_application's other default
-- template inserts). A separate backfill migration (028) does the same
-- for clients that already existed before this ran.
--
-- Safe to re-run.

create table if not exists resource_vault_templates (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  title           text not null,
  description     text,
  storage_path    text,
  sort_order      integer not null default 0,
  created_at      timestamptz not null default now()
);

alter table resource_vault_templates enable row level security;

drop policy if exists resource_vault_templates_select on resource_vault_templates;
create policy resource_vault_templates_select on resource_vault_templates for select
using ( is_org_member(organization_id) or is_super_admin() );

drop policy if exists resource_vault_templates_write on resource_vault_templates;
create policy resource_vault_templates_write on resource_vault_templates for all
using ( is_super_admin() )
with check ( is_super_admin() );

alter table client_resource_vault_items alter column url drop not null;
alter table client_resource_vault_items alter column title drop not null;
alter table client_resource_vault_items add column if not exists storage_path text;
alter table client_resource_vault_items add column if not exists template_id uuid references resource_vault_templates(id) on delete cascade;

-- ----------------------------------------------------------------------
-- Storage: same bucket as everything else (client-documents), new path
-- prefix resource-templates/{organization_id}/{filename}. Write is
-- Super-Admin-only (managing the shared master list is an admin task,
-- same as everything else gated behind is_super_admin() in this app).
-- Read is open to anyone -- these files are explicitly meant to be shown
-- to every client (both staff editing and the anonymous client-facing
-- dashboard), so there's no per-row confidentiality to gate here the way
-- there is for a specific client's own uploaded documents.
-- ----------------------------------------------------------------------

drop policy if exists "resource-templates read" on storage.objects;
create policy "resource-templates read" on storage.objects for select
using (
  bucket_id = 'client-documents'
  and (storage.foldername(name))[1] = 'resource-templates'
);

drop policy if exists "resource-templates write" on storage.objects;
create policy "resource-templates write" on storage.objects for all
using (
  bucket_id = 'client-documents'
  and (storage.foldername(name))[1] = 'resource-templates'
  and is_super_admin()
)
with check (
  bucket_id = 'client-documents'
  and (storage.foldername(name))[1] = 'resource-templates'
  and is_super_admin()
);

-- ----------------------------------------------------------------------
-- Seed the 8 default EG templates for every existing organization.
-- storage_path starts null -- Greg uploads the actual files from the new
-- Resource Templates admin page afterward. Wording taken from Greg's
-- reference screenshot (a few titles/descriptions were truncated there,
-- best-guess filled in -- easy to correct from the admin page once seen).
-- ----------------------------------------------------------------------

insert into resource_vault_templates (organization_id, title, description, sort_order)
select o.id, t.title, t.description, t.sort_order
from organizations o
cross join (
  values
    ('EG – What to Expect', 'What to Expect', 1),
    ('EG FAQs', 'FAQs for the CEO', 2),
    ('EG 5 Framework Videos', '5 Framework Videos - Password Protected', 3),
    ('Keirsey Work Style Preference', 'Take the Temperament Test', 4),
    ('EG Marketing Principles', 'Marketing Principles', 5),
    ('EG Frameworks Overview', 'Quick Overview', 6),
    ('Intercept Marketing Image', 'Visualization', 7),
    ('Signals of Change', 'Signals of Change', 8)
) as t(title, description, sort_order)
where not exists (
  select 1 from resource_vault_templates existing where existing.organization_id = o.id
);

-- ----------------------------------------------------------------------
-- accept_client_application: identical to 025's version except it also
-- links every one of the organization's Resource Vault templates into the
-- new client's Resource Vault.
-- ----------------------------------------------------------------------
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
begin
  if not is_super_admin() then
    raise exception 'Only a Super Admin can accept an application (Section 5.2)';
  end if;

  select * into v_app from client_applications
    where id = p_application_id and status = 'pending';
  if not found then
    raise exception 'Application not found or already processed';
  end if;

  insert into clients (organization_id, econ_dev_company_id, name, slug, budget_hours_available, created_by)
  values (v_app.organization_id, v_app.econ_dev_company_id, v_app.company_name, p_slug, p_budget_hours_available, auth.uid())
  returning id into v_client_id;

  insert into client_content (client_id) values (v_client_id);
  insert into client_share_links (client_id, subdomain) values (v_client_id, p_slug);

  -- Team Leader — the one row that's actually "the" Team Lead for RLS
  -- purposes (is_team_lead = true). hours_allotted starts at 0 here on
  -- purpose; the app sets it right after via a follow-up UPDATE (see
  -- client_applications.html submitAccept()).
  insert into client_assignments (client_id, user_id, specialty_type, slot_number, hours_allotted, is_team_lead)
  values (v_client_id, p_team_lead_id, 'team_lead', 1, 0, true);

  -- The rest of the default template — one row per specialty, unassigned,
  -- edited later from the Client Workspace table. Admin and QC get the
  -- hours the Super Admin set on the Accept form (defaults 2 and 3);
  -- everything else starts blank. A second (or third) slot of any
  -- specialty is added via "+ Add row" only when a client actually needs it.
  insert into client_assignments (client_id, user_id, specialty_type, slot_number, hours_allotted, is_team_lead) values
    (v_client_id, null, 'market_research',   1, 0,            false),
    (v_client_id, null, 'digital_marketing', 1, 0,            false),
    (v_client_id, null, 'gis',               1, 0,            false),
    (v_client_id, null, 'watering_holes',    1, 0,            false),
    (v_client_id, null, 'admin',             1, p_admin_hours, false),
    (v_client_id, null, 'quality_control',   1, p_qc_hours,    false);

  -- Standard Project Next Steps template (Section 4.3) — the same 6 steps
  -- every engagement follows. Notes are pre-filled except the first two,
  -- which need an actual date/time from the Team Lead once scheduled.
  insert into client_next_steps (client_id, description, notes, completed, sort_order) values
    (v_client_id, 'Send EG Invitation Email', null, false, 1),
    (v_client_id, 'Discovery Call', null, false, 2),
    (v_client_id, 'Controlling Document', 'Agree on documented research approach', false, 3),
    (v_client_id, 'Research Controlling Document', 'Assign EG team to research areas', false, 4),
    (v_client_id, 'Client Research Review Call', 'Zoom Call with Researchers', false, 5),
    (v_client_id, 'Close-Out Survey', 'How did we do?', false, 6);

  -- Standard Resource Vault — every one of the org's shared templates gets
  -- linked in. title/description/storage_path stay null on the client's
  -- row; they always resolve from the template wherever this is read.
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
-- get_client_public_view: identical to 025's version except the
-- resource_vault jsonb_build_object resolves title/description/file from
-- the linked template when template_id is set, and gains storage_path
-- (both from the row itself, for custom uploads, and from the template).
-- ----------------------------------------------------------------------
drop function if exists get_client_public_view(text);

create or replace function get_client_public_view(p_slug text)
returns table (
  client_status  client_status,
  client_name    text,
  company        jsonb,
  workflow       jsonb,
  research_areas jsonb,
  documents      jsonb,
  contacts       jsonb,
  competitors    jsonb,
  top_customers  jsonb,
  resource_vault jsonb,
  next_steps     jsonb,
  team           jsonb
)
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_client clients;
begin
  select c.* into v_client
  from clients c
  join client_share_links l on l.client_id = c.id
  where l.subdomain = p_slug and l.active;

  if not found then
    raise exception 'Not found';
  end if;

  if v_client.status = 'finalized' then
    return query
      select
        v_client.status, v_client.name, s.company, s.workflow, s.research_areas,
        s.documents, s.contacts, s.competitors, s.top_customers, s.resource_vault,
        s.next_steps, s.team
      from engagement_snapshots s
      where s.client_id = v_client.id
      order by s.created_at desc
      limit 1;
  else
    return query
      select
        v_client.status,
        v_client.name,
        jsonb_build_object(
          'logo_url', v_client.logo_url,
          'website_url', v_client.website_url,
          'address', v_client.address,
          'description', v_client.description,
          'naics_codes', v_client.naics_codes,
          'brand_name', v_client.brand_name,
          'brand_url', v_client.brand_url,
          'linkedin_url', v_client.linkedin_url,
          'facebook_url', v_client.facebook_url,
          'instagram_url', v_client.instagram_url,
          'twitter_url', v_client.twitter_url,
          'youtube_url', v_client.youtube_url
        ),
        coalesce((
          select jsonb_build_object(
            'discovery_doc_url', cc.discovery_doc_url,
            'controlling_doc_url', cc.controlling_doc_url,
            'research_review_url', cc.research_review_url,
            'closeout_survey_url', cc.closeout_survey_url
          )
          from client_content cc where cc.client_id = v_client.id
        ), '{}'::jsonb),
        coalesce((
          select jsonb_object_agg(area, docs)
          from (
            select rat.area::text as area,
              coalesce((
                select jsonb_agg(jsonb_build_object('file_name', d.file_name, 'storage_path', d.storage_path))
                from documents d
                where d.client_id = v_client.id and d.visibility = 'client_facing' and d.research_area = rat.area
              ), '[]'::jsonb) as docs
            from unnest(enum_range(null::research_area_type)) as rat(area)
          ) areas
        ), '{}'::jsonb),
        coalesce((
          select jsonb_agg(jsonb_build_object('file_name', d.file_name, 'storage_path', d.storage_path))
          from documents d
          where d.client_id = v_client.id and d.visibility = 'client_facing' and d.research_area is null
        ), '[]'::jsonb),
        coalesce((
          select jsonb_agg(jsonb_build_object('name', c.name, 'title', c.title, 'email', c.email, 'phone', c.phone) order by c.sort_order)
          from client_contacts c where c.client_id = v_client.id
        ), '[]'::jsonb),
        coalesce((
          select jsonb_agg(jsonb_build_object('name', c.name, 'website_url', c.website_url, 'notes', c.notes) order by c.sort_order)
          from client_competitors c where c.client_id = v_client.id
        ), '[]'::jsonb),
        coalesce((
          select jsonb_agg(jsonb_build_object('name', c.name, 'website_url', c.website_url, 'notes', c.notes) order by c.sort_order)
          from client_top_customers c where c.client_id = v_client.id
        ), '[]'::jsonb),
        coalesce((
          select jsonb_agg(jsonb_build_object(
            'title', coalesce(r.title, rvt.title),
            'description', coalesce(r.description, rvt.description),
            'url', r.url,
            'storage_path', coalesce(r.storage_path, rvt.storage_path)
          ) order by r.sort_order)
          from client_resource_vault_items r
          left join resource_vault_templates rvt on rvt.id = r.template_id
          where r.client_id = v_client.id
        ), '[]'::jsonb),
        coalesce((
          select jsonb_agg(jsonb_build_object('description', n.description, 'notes', n.notes, 'completed', n.completed) order by n.sort_order)
          from client_next_steps n where n.client_id = v_client.id
        ), '[]'::jsonb),
        coalesce((
          select jsonb_agg(jsonb_build_object('name', u.full_name, 'specialty', ca.specialty_type) order by ca.specialty_type, ca.slot_number)
          from client_assignments ca join users u on u.id = ca.user_id
          where ca.client_id = v_client.id and ca.user_id is not null
        ), '[]'::jsonb);
  end if;
end;
$$;

grant usage on schema public to anon;
grant execute on function get_client_public_view(text) to anon;

-- ----------------------------------------------------------------------
-- finalize_client: identical to 025's version except the resource_vault
-- jsonb_build_object resolves from the template the same way (freezing
-- whatever the template says at close time into the snapshot).
-- ----------------------------------------------------------------------
drop function if exists finalize_client(uuid);

create or replace function finalize_client(p_client_id uuid)
returns uuid
language plpgsql
security invoker
as $$
declare
  v_client      clients;
  v_snapshot_id uuid;
  v_research    jsonb;
  v_company     jsonb;
  v_workflow    jsonb;
begin
  if not (is_super_admin() or is_team_lead_of_client(p_client_id)) then
    raise exception 'Only a Super Admin or the client''s Team Lead can finalize an engagement (Section 4.1)';
  end if;

  select * into v_client from clients where id = p_client_id;

  v_company := jsonb_build_object(
    'logo_url', v_client.logo_url,
    'website_url', v_client.website_url,
    'address', v_client.address,
    'description', v_client.description,
    'naics_codes', v_client.naics_codes,
    'brand_name', v_client.brand_name,
    'brand_url', v_client.brand_url,
    'linkedin_url', v_client.linkedin_url,
    'facebook_url', v_client.facebook_url,
    'instagram_url', v_client.instagram_url,
    'twitter_url', v_client.twitter_url,
    'youtube_url', v_client.youtube_url
  );

  select jsonb_build_object(
    'discovery_doc_url', discovery_doc_url,
    'controlling_doc_url', controlling_doc_url,
    'research_review_url', research_review_url,
    'closeout_survey_url', closeout_survey_url
  )
  into v_workflow
  from client_content where client_id = p_client_id;

  select jsonb_object_agg(area, docs) into v_research
  from (
    select rat.area::text as area,
      coalesce((
        select jsonb_agg(jsonb_build_object('file_name', d.file_name, 'storage_path', d.storage_path))
        from documents d
        where d.client_id = p_client_id and d.visibility = 'client_facing' and d.research_area = rat.area
      ), '[]'::jsonb) as docs
    from unnest(enum_range(null::research_area_type)) as rat(area)
  ) areas;

  insert into engagement_snapshots (
    client_id, research_areas, documents, company, workflow,
    contacts, competitors, top_customers, resource_vault, next_steps, team
  )
  select
    p_client_id,
    coalesce(v_research, '{}'::jsonb),
    coalesce((
      select jsonb_agg(jsonb_build_object('file_name', d.file_name, 'storage_path', d.storage_path))
      from documents d
      where d.client_id = p_client_id and d.visibility = 'client_facing' and d.research_area is null
    ), '[]'::jsonb),
    coalesce(v_company, '{}'::jsonb),
    coalesce(v_workflow, '{}'::jsonb),
    coalesce((
      select jsonb_agg(jsonb_build_object('name', c.name, 'title', c.title, 'email', c.email, 'phone', c.phone) order by c.sort_order)
      from client_contacts c where c.client_id = p_client_id
    ), '[]'::jsonb),
    coalesce((
      select jsonb_agg(jsonb_build_object('name', c.name, 'website_url', c.website_url, 'notes', c.notes) order by c.sort_order)
      from client_competitors c where c.client_id = p_client_id
    ), '[]'::jsonb),
    coalesce((
      select jsonb_agg(jsonb_build_object('name', c.name, 'website_url', c.website_url, 'notes', c.notes) order by c.sort_order)
      from client_top_customers c where c.client_id = p_client_id
    ), '[]'::jsonb),
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'title', coalesce(r.title, rvt.title),
        'description', coalesce(r.description, rvt.description),
        'url', r.url,
        'storage_path', coalesce(r.storage_path, rvt.storage_path)
      ) order by r.sort_order)
      from client_resource_vault_items r
      left join resource_vault_templates rvt on rvt.id = r.template_id
      where r.client_id = p_client_id
    ), '[]'::jsonb),
    coalesce((
      select jsonb_agg(jsonb_build_object('description', n.description, 'notes', n.notes, 'completed', n.completed) order by n.sort_order)
      from client_next_steps n where n.client_id = p_client_id
    ), '[]'::jsonb),
    coalesce((
      select jsonb_agg(jsonb_build_object('name', u.full_name, 'specialty', ca.specialty_type) order by ca.specialty_type, ca.slot_number)
      from client_assignments ca join users u on u.id = ca.user_id
      where ca.client_id = p_client_id and ca.user_id is not null
    ), '[]'::jsonb)
  returning id into v_snapshot_id;

  update clients set status = 'finalized', date_closed = current_date, updated_at = now()
  where id = p_client_id;

  insert into audit_log (client_id, user_id, action, field, new_value)
  values (p_client_id, auth.uid(), 'client_finalized', 'status', 'finalized');

  return v_snapshot_id;
end;
$$;
