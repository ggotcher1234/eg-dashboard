-- 033_research_questions.sql
--
-- Depends on 019_client_profile_content.sql (research_area_type,
-- documents.research_area) and 032_workflow_document_uploads.sql.
--
-- Greg's reference tool structures each research area (Market Dynamics,
-- Outbound Marketing, Inbound Marketing, Watering Holes) as: one or more
-- "Questions" the research is trying to answer, and each question has one
-- or several uploaded files that answer it. Our Documents section only had
-- a flat upload box + a dropdown to tag a file with an area -- no concept
-- of a question at all.
--
-- New table client_research_questions holds the questions themselves.
-- documents gains a nullable question_id -- a document attached to a
-- question lives under it; anything uploaded the old way (research_area
-- set, no question) is left alone and still shows up (as an "unsorted"
-- bucket for that area, both in the editor and the public view) rather
-- than silently disappearing.
--
-- Safe to re-run.

create table if not exists client_research_questions (
  id            uuid primary key default gen_random_uuid(),
  client_id     uuid not null references clients(id) on delete cascade,
  research_area research_area_type not null,
  question      text,
  sort_order    integer not null default 0,
  created_at    timestamptz not null default now()
);

alter table client_research_questions enable row level security;

drop policy if exists client_research_questions_select on client_research_questions;
create policy client_research_questions_select on client_research_questions for select
using ( is_super_admin() or is_assigned_to_client(client_id) );

drop policy if exists client_research_questions_write on client_research_questions;
create policy client_research_questions_write on client_research_questions for all
using ( is_super_admin() or is_assigned_to_client(client_id) )
with check ( is_super_admin() or is_assigned_to_client(client_id) );

alter table documents add column if not exists question_id uuid references client_research_questions(id) on delete cascade;
create index if not exists idx_documents_question on documents(question_id);

-- ----------------------------------------------------------------------
-- get_client_public_view: identical to 032's version except the
-- `research_areas` bundle is now nested by question. Per area: each
-- question (in order) with its client-facing documents, plus -- if any
-- exist -- a trailing entry (question: null) for documents tagged with
-- that area the old flat way, before questions existed.
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
-- finalize_client: identical to 032's version except the `research_areas`
-- snapshot builder is nested by question the same way.
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
