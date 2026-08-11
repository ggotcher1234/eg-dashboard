-- 045_top_business_issues.sql
--
-- Depends on 041_team_partner_contacts_merge.sql (get_client_public_view /
-- finalize_client) and 043_company_info_from_application.sql
-- (accept_client_application).
--
-- Greg: "let's add this field from the application to the Dashboard Preview
-- Page under the Company Description." "Top Business Issues" is the intake
-- form's `client_applications.top_business_issues` -- "What is this company
-- trying to solve?" -- same tier as Company Description, so it gets the
-- same treatment 043 gave address/website/naics_codes: a new column on
-- `clients`, copied automatically at acceptance, backfilled for clients
-- already accepted, editable on Company Information, and now also carried
-- through the public-view bundle so it actually shows on the client
-- dashboard (043 only handled the three fields with no public-view
-- exposure need -- this one needs to render, so `company` jsonb gains it
-- too).
--
-- Four parts:
--   1. alter table clients -- add top_business_issues.
--   2. accept_client_application() -- identical to 043's version except the
--      insert into clients also copies top_business_issues from the
--      application.
--   3. get_client_public_view() / finalize_client() -- identical to 041's
--      versions except the `company` jsonb_build_object gains
--      'top_business_issues'. Every other field (workflow storage paths,
--      nested research questions, location fields, resource vault url
--      coalesce, team email/phone + merged partner contacts) is carried
--      forward unchanged from 041.
--   4. One-time backfill for clients accepted before this migration
--      existed, same "only fill blanks, never overwrite" rule as 043.
--
-- Safe to re-run.

alter table clients add column if not exists top_business_issues text;

-- ----------------------------------------------------------------------
-- 2. accept_client_application()
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

  update client_applications
    set status = 'accepted', client_id = v_client_id, reviewed_by = auth.uid(), reviewed_at = now()
    where id = p_application_id;

  insert into audit_log (client_id, user_id, action, field, new_value)
  values (v_client_id, auth.uid(), 'client_accepted', 'status', 'active');

  return v_client_id;
end;
$$;

-- ----------------------------------------------------------------------
-- 3. get_client_public_view() / finalize_client()
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
          'top_business_issues', v_client.top_business_issues,
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
            'discovery_doc_storage_path', cc.discovery_doc_storage_path,
            'controlling_doc_url', cc.controlling_doc_url,
            'controlling_doc_storage_path', cc.controlling_doc_storage_path,
            'research_review_url', cc.research_review_url,
            'closeout_survey_url', cc.closeout_survey_url,
            'closeout_survey_storage_path', cc.closeout_survey_storage_path
          )
          from client_content cc where cc.client_id = v_client.id
        ), '{}'::jsonb),
        coalesce((
          select jsonb_object_agg(area, payload)
          from (
            select rat.area::text as area,
              coalesce((
                select jsonb_agg(entry order by entry_sort)
                from (
                  select q.sort_order as entry_sort,
                    jsonb_build_object(
                      'question', q.question,
                      'documents', coalesce((
                        select jsonb_agg(jsonb_build_object('file_name', d.file_name, 'storage_path', d.storage_path))
                        from documents d
                        where d.question_id = q.id and d.visibility = 'client_facing'
                      ), '[]'::jsonb)
                    ) as entry
                  from client_research_questions q
                  where q.client_id = v_client.id and q.research_area = rat.area
                    and (
                      coalesce(nullif(trim(q.question), ''), '') <> ''
                      or exists (select 1 from documents d where d.question_id = q.id and d.visibility = 'client_facing')
                    )
                  union all
                  select 2147483647 as entry_sort,
                    jsonb_build_object(
                      'question', null,
                      'documents', jsonb_agg(jsonb_build_object('file_name', d2.file_name, 'storage_path', d2.storage_path))
                    ) as entry
                  from documents d2
                  where d2.client_id = v_client.id and d2.research_area = rat.area
                    and d2.question_id is null and d2.visibility = 'client_facing'
                  having count(*) > 0
                ) combined
              ), '[]'::jsonb) as payload
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
          select jsonb_agg(jsonb_build_object('name', c.name, 'website_url', c.website_url, 'location', c.location, 'notes', c.notes) order by c.sort_order)
          from client_competitors c where c.client_id = v_client.id
        ), '[]'::jsonb),
        coalesce((
          select jsonb_agg(jsonb_build_object('name', c.name, 'website_url', c.website_url, 'location', c.location, 'notes', c.notes) order by c.sort_order)
          from client_top_customers c where c.client_id = v_client.id
        ), '[]'::jsonb),
        coalesce((
          select jsonb_agg(jsonb_build_object(
            'title', coalesce(r.title, rvt.title),
            'description', coalesce(r.description, rvt.description),
            'url', coalesce(r.url, rvt.url),
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
          select jsonb_agg(jsonb_build_object('name', u.full_name, 'specialty', ca.specialty_type, 'email', u.email, 'phone', u.phone) order by ca.specialty_type, ca.slot_number)
          from client_assignments ca join users u on u.id = ca.user_id
          where ca.client_id = v_client.id and ca.user_id is not null
        ), '[]'::jsonb)
        ||
        coalesce((
          select jsonb_agg(jsonb_build_object('name', pc.name, 'specialty', pc.title, 'email', pc.email, 'phone', pc.phone) order by ctpc.sort_order)
          from client_team_partner_contacts ctpc
          join econ_dev_partner_contacts pc on pc.id = ctpc.partner_contact_id
          where ctpc.client_id = v_client.id and pc.active
        ), '[]'::jsonb);
  end if;
end;
$$;

grant usage on schema public to anon;
grant execute on function get_client_public_view(text) to anon;

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
    'top_business_issues', v_client.top_business_issues,
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
    'discovery_doc_storage_path', discovery_doc_storage_path,
    'controlling_doc_url', controlling_doc_url,
    'controlling_doc_storage_path', controlling_doc_storage_path,
    'research_review_url', research_review_url,
    'closeout_survey_url', closeout_survey_url,
    'closeout_survey_storage_path', closeout_survey_storage_path
  )
  into v_workflow
  from client_content where client_id = p_client_id;

  select jsonb_object_agg(area, payload) into v_research
  from (
    select rat.area::text as area,
      coalesce((
        select jsonb_agg(entry order by entry_sort)
        from (
          select q.sort_order as entry_sort,
            jsonb_build_object(
              'question', q.question,
              'documents', coalesce((
                select jsonb_agg(jsonb_build_object('file_name', d.file_name, 'storage_path', d.storage_path))
                from documents d
                where d.question_id = q.id and d.visibility = 'client_facing'
              ), '[]'::jsonb)
            ) as entry
          from client_research_questions q
          where q.client_id = p_client_id and q.research_area = rat.area
            and (
              coalesce(nullif(trim(q.question), ''), '') <> ''
              or exists (select 1 from documents d where d.question_id = q.id and d.visibility = 'client_facing')
            )
          union all
          select 2147483647 as entry_sort,
            jsonb_build_object(
              'question', null,
              'documents', jsonb_agg(jsonb_build_object('file_name', d2.file_name, 'storage_path', d2.storage_path))
            ) as entry
          from documents d2
          where d2.client_id = p_client_id and d2.research_area = rat.area
            and d2.question_id is null and d2.visibility = 'client_facing'
          having count(*) > 0
        ) combined
      ), '[]'::jsonb) as payload
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
      select jsonb_agg(jsonb_build_object('name', c.name, 'website_url', c.website_url, 'location', c.location, 'notes', c.notes) order by c.sort_order)
      from client_competitors c where c.client_id = p_client_id
    ), '[]'::jsonb),
    coalesce((
      select jsonb_agg(jsonb_build_object('name', c.name, 'website_url', c.website_url, 'location', c.location, 'notes', c.notes) order by c.sort_order)
      from client_top_customers c where c.client_id = p_client_id
    ), '[]'::jsonb),
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'title', coalesce(r.title, rvt.title),
        'description', coalesce(r.description, rvt.description),
        'url', coalesce(r.url, rvt.url),
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
      select jsonb_agg(jsonb_build_object('name', u.full_name, 'specialty', ca.specialty_type, 'email', u.email, 'phone', u.phone) order by ca.specialty_type, ca.slot_number)
      from client_assignments ca join users u on u.id = ca.user_id
      where ca.client_id = p_client_id and ca.user_id is not null
    ), '[]'::jsonb)
    ||
    coalesce((
      select jsonb_agg(jsonb_build_object('name', pc.name, 'specialty', pc.title, 'email', pc.email, 'phone', pc.phone) order by ctpc.sort_order)
      from client_team_partner_contacts ctpc
      join econ_dev_partner_contacts pc on pc.id = ctpc.partner_contact_id
      where ctpc.client_id = p_client_id and pc.active
    ), '[]'::jsonb)
  returning id into v_snapshot_id;

  update clients set status = 'finalized', date_closed = current_date, updated_at = now()
  where id = p_client_id;

  insert into audit_log (client_id, user_id, action, field, new_value)
  values (p_client_id, auth.uid(), 'client_finalized', 'status', 'finalized');

  return v_snapshot_id;
end;
$$;

-- ----------------------------------------------------------------------
-- 4. One-time backfill for clients accepted before this migration existed.
-- Only fills top_business_issues if it's currently null AND the original
-- application actually had a value -- never overwrites anything already
-- there.
-- ----------------------------------------------------------------------
update clients c
set top_business_issues = coalesce(c.top_business_issues, a.top_business_issues)
from client_applications a
where a.client_id = c.id
  and c.top_business_issues is null
  and a.top_business_issues is not null;
