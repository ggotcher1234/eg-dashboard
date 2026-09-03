-- 107_research_docs_flat_order.sql
--
-- Depends on 105_document_display_name.sql (the current
-- get_client_public_view() / finalize_client() bodies this copies).
--
-- Greg (9/2/26): "the file order sequence for Inbound Marketing on
-- client_research.html and the client dashboard are different and should
-- match." Cause: client_research.html renders each research area's
-- documents as ONE flat list ordered by sort_order (it dropped per-question
-- grouping on 8/26/26), but get_client_public_view() still grouped docs by
-- question_id -- so any legacy doc still tied to a question sorted ahead of
-- the "no question" bucket on the dashboard, a grouping the admin page has
-- no UI for and the dashboard never displays anyway.
--
-- Fix: build research_areas as a single flat list per area of every
-- client-facing document (question-attached or not), ordered exactly like
-- client_research.html's loadDocuments():
--   order by sort_order asc nulls last, uploaded_at desc, id
-- The shape stays [{question: null, documents: [...]}] so client_public.html
-- (renderResearchAreaBody) needs no change -- it only ever rendered
-- entry.documents, never entry.question.
--
-- Bodies below are the full, current 105 versions with only the
-- research_areas subquery changed, in both functions. Already-finalized
-- engagements keep their old snapshot order until re-finalized -- acceptable.
--
-- Safe to re-run.

alter table documents add column if not exists display_name text;

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
          'youtube_url', v_client.youtube_url,
          'program_name', (
            select edc.name from econ_dev_companies edc where edc.id = v_client.econ_dev_company_id
          )
        ),
        coalesce((
          select jsonb_build_object(
            'discovery_doc_url', cc.discovery_doc_url,
            'discovery_doc_storage_path', cc.discovery_doc_storage_path,
            'controlling_doc_url', cc.controlling_doc_url,
            'controlling_doc_storage_path', cc.controlling_doc_storage_path,
            'controlling_doc_link_url', cc.controlling_doc_link_url,
            'research_review_url', cc.research_review_url,
            'research_review_storage_path', cc.research_review_storage_path,
            'closeout_survey_url', cc.closeout_survey_url,
            'closeout_survey_storage_path', cc.closeout_survey_storage_path,
            'evaluation_link_url', cc.evaluation_link_url,
            'evaluation_submitted_at', (
              select max(r.submitted_at) from client_evaluation_responses r where r.client_id = v_client.id
            ),
            'evaluation_response', (
              select jsonb_build_object(
                'submitted_at', r.submitted_at,
                'respondent_name', r.respondent_name,
                'respondent_date', r.respondent_date,
                'question_ratings', r.question_ratings,
                'q1_explain', r.q1_explain,
                'prepared', r.prepared,
                'prepared_explain', r.prepared_explain,
                'improvement_suggestions', r.improvement_suggestions,
                'nps_score', r.nps_score,
                'nps_explain', r.nps_explain,
                'referrals', r.referrals,
                'testimonial', r.testimonial,
                'very_useful_count', r.very_useful_count,
                'partially_useful_count', r.partially_useful_count,
                'not_useful_count', r.not_useful_count,
                'weighted_score', r.weighted_score,
                'weighted_max', r.weighted_max
              )
              from client_evaluation_responses r
              where r.client_id = v_client.id
              order by r.submitted_at desc
              limit 1
            )
          )
          from client_content cc where cc.client_id = v_client.id
        ), '{}'::jsonb),
        coalesce((
          select jsonb_object_agg(area, payload)
          from (
            select rat.area::text as area,
              jsonb_build_array(jsonb_build_object(
                'question', null,
                'documents', coalesce((
                  select jsonb_agg(
                    jsonb_build_object('file_name', d.file_name, 'display_name', d.display_name, 'storage_path', d.storage_path, 'url', d.url)
                    order by d.sort_order asc nulls last, d.uploaded_at desc, d.id
                  )
                  from documents d
                  where d.client_id = v_client.id and d.research_area = rat.area and d.visibility = 'client_facing'
                ), '[]'::jsonb)
              )) as payload
            from unnest(enum_range(null::research_area_type)) as rat(area)
          ) areas
        ), '{}'::jsonb),
        coalesce((
          select jsonb_agg(jsonb_build_object('file_name', d.file_name, 'display_name', d.display_name, 'storage_path', d.storage_path, 'url', d.url) order by d.sort_order nulls last, d.uploaded_at desc)
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
    'youtube_url', v_client.youtube_url,
    'program_name', (
      select edc.name from econ_dev_companies edc where edc.id = v_client.econ_dev_company_id
    )
  );

  select jsonb_build_object(
    'discovery_doc_url', discovery_doc_url,
    'discovery_doc_storage_path', discovery_doc_storage_path,
    'controlling_doc_url', controlling_doc_url,
    'controlling_doc_storage_path', controlling_doc_storage_path,
    'controlling_doc_link_url', controlling_doc_link_url,
    'research_review_url', research_review_url,
    'research_review_storage_path', research_review_storage_path,
    'closeout_survey_url', closeout_survey_url,
    'closeout_survey_storage_path', closeout_survey_storage_path,
    'evaluation_link_url', evaluation_link_url,
    'evaluation_submitted_at', (
      select max(r.submitted_at) from client_evaluation_responses r where r.client_id = p_client_id
    ),
    'evaluation_response', (
      select jsonb_build_object(
        'submitted_at', r.submitted_at,
        'respondent_name', r.respondent_name,
        'respondent_date', r.respondent_date,
        'question_ratings', r.question_ratings,
        'q1_explain', r.q1_explain,
        'prepared', r.prepared,
        'prepared_explain', r.prepared_explain,
        'improvement_suggestions', r.improvement_suggestions,
        'nps_score', r.nps_score,
        'nps_explain', r.nps_explain,
        'referrals', r.referrals,
        'testimonial', r.testimonial,
        'very_useful_count', r.very_useful_count,
        'partially_useful_count', r.partially_useful_count,
        'not_useful_count', r.not_useful_count,
        'weighted_score', r.weighted_score,
        'weighted_max', r.weighted_max
      )
      from client_evaluation_responses r
      where r.client_id = p_client_id
      order by r.submitted_at desc
      limit 1
    )
  )
  into v_workflow
  from client_content where client_id = p_client_id;

  select jsonb_object_agg(area, payload) into v_research
  from (
    select rat.area::text as area,
      jsonb_build_array(jsonb_build_object(
        'question', null,
        'documents', coalesce((
          select jsonb_agg(
            jsonb_build_object('file_name', d.file_name, 'display_name', d.display_name, 'storage_path', d.storage_path, 'url', d.url)
            order by d.sort_order asc nulls last, d.uploaded_at desc, d.id
          )
          from documents d
          where d.client_id = p_client_id and d.research_area = rat.area and d.visibility = 'client_facing'
        ), '[]'::jsonb)
      )) as payload
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
      select jsonb_agg(jsonb_build_object('file_name', d.file_name, 'display_name', d.display_name, 'storage_path', d.storage_path, 'url', d.url) order by d.sort_order nulls last, d.uploaded_at desc)
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
