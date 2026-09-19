-- 123_show_research_questions.sql   (9/19/26)
--
-- Greg: "let's add a small option on this page to show the questions on the
-- EG Dashboard. the default should be no." One switch per engagement.
--
-- Two parts:
--   1. clients.show_research_questions -- boolean, NOT NULL, default false, so
--      every engagement that exists today and every one created tomorrow keeps
--      the current behaviour until somebody deliberately turns it on.
--   2. get_client_public_view() -- the research questions were dropped from
--      this payload on 8/28/26 ("research questions are what the CEO close-out
--      survey asks about, not something meant for the client-facing
--      dashboard"), so today the client dashboard has no way to show them even
--      if it wanted to. Each area now carries its questions ahead of its
--      documents, but ONLY for an engagement with the switch on. With it off
--      the payload is byte-for-byte what it is now, which is what makes this
--      safe to deploy before anyone flips a switch.
--
-- This is 115_public_view_updated_at.sql's function body, unchanged except for
-- the research_areas block. Safe to re-run.
--
-- NOT COVERED, deliberately: finalize_client() freezes a snapshot of this
-- payload for a finalized engagement. A snapshot taken before this migration
-- has no questions in it, and re-finalizing is what would refresh it -- a
-- frozen dashboard should not change under a client's feet because a flag
-- moved.

alter table clients
  add column if not exists show_research_questions boolean not null default false;

comment on column clients.show_research_questions is
  'Client dashboard shows this engagement''s research questions above each area''s documents. Set from Add Research. Default false.';

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
          ),
          'updated_at', greatest(
            v_client.updated_at,
            v_client.last_activity_at,
            (select max(d.uploaded_at) from documents d
              where d.client_id = v_client.id and d.visibility = 'client_facing')
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
        -- research_areas: one key per area. Each value is an array of
        -- { question, documents } entries -- the questions (documents: [])
        -- when this engagement opts in, then the single trailing entry
        -- (question: null) that carries the area's client-facing documents.
        -- With the switch off the questions array is empty and this collapses
        -- to exactly the payload 115 produced.
        coalesce((
          select jsonb_object_agg(area, payload)
          from (
            select rat.area::text as area,
              (
                case when v_client.show_research_questions then coalesce((
                  select jsonb_agg(
                    jsonb_build_object('question', q.question, 'documents', '[]'::jsonb)
                    order by q.sort_order asc, q.created_at asc, q.id
                  )
                  from client_research_questions q
                  where q.client_id = v_client.id
                    and q.research_area = rat.area
                    -- a blank question row is a half-typed one, not content
                    and coalesce(btrim(q.question), '') <> ''
                ), '[]'::jsonb) else '[]'::jsonb end
              )
              ||
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
