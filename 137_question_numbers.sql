-- 137_question_numbers.sql   (10/3/26)
--
-- Punch list #1, settled by Greg: "the 'current' (most recent saved) is the
-- one that will drive the question numbers. add a question # dropdown next to
-- question with 1-9 as we never have more than 9 questions."
--
-- So the number is NOT derived and NOT frozen at some "finalised" moment that
-- does not exist in the schema. It is a value a Team Lead picks on the
-- Controlling Document, and whatever the most recent save holds is the number
-- that question carries everywhere else -- the client's dashboard, the
-- client-facing Controlling Document, and the close-out Evaluation Sheet.
-- That removes the blocker recorded on the punch list: no finalised flag is
-- needed, because the saved row IS the source of truth.
--
-- Until now any numbering was typed into the question text itself ("1. Where
-- is the opportunity?") and the downstream pages printed it verbatim. That
-- worked but could not be relied on: nothing stopped two questions being
-- typed as 3, nothing renumbered when the text was edited, and the close-out
-- survey had no way to know a question's number at all.
--
-- 1 to 9, nullable. Nullable because a half-typed row with no number must
-- still save -- the dropdown starts empty, and a question nobody numbered is
-- shown without one rather than blocking the save.
--
-- Duplicates are deliberately NOT blocked at the database level. A Team Lead
-- renumbering four questions passes through states where two briefly share a
-- number, and a unique index would make the save fail halfway through with
-- some rows written and some not. The Controlling Document flags a duplicate
-- in the form instead, where it can be seen and fixed.
--
-- No DROP statements anywhere in this file: destructive statements hang on
-- this connection rather than erroring, so every object is created with
-- "if not exists" or "create or replace".
--
-- Safe to re-run.

-- ---------- 1. the column ----------
alter table client_research_questions
  add column if not exists question_number smallint;

comment on column client_research_questions.question_number is
  'The number this question is known by, 1-9, chosen on the Controlling '
  'Document. Carries through to the client dashboard, the client-facing '
  'Controlling Document and the Evaluation Sheet. Null means unnumbered.';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'client_research_questions_number_range'
      and conrelid = 'client_research_questions'::regclass
  ) then
    alter table client_research_questions
      add constraint client_research_questions_number_range
      check (question_number is null or question_number between 1 and 9);
  end if;
end $$;

-- ---------- 2. backfill ----------
-- Existing engagements get the order they are already displayed in: by area,
-- then by sort_order within the area -- which is exactly the order the
-- Controlling Document lays them out on screen today. Blank rows are skipped
-- (a half-typed row is not a question), and anything past the ninth is left
-- null rather than silently truncated to 9.
with ranked as (
  select
    id,
    row_number() over (
      partition by client_id
      order by research_area, sort_order nulls last, created_at, id
    ) as n
  from client_research_questions
  where coalesce(btrim(question), '') <> ''
)
update client_research_questions q
set question_number = r.n
from ranked r
where q.id = r.id
  and q.question_number is null
  and r.n <= 9;

-- ---------- 3. the client-facing Controlling Document ----------
-- Adds question_number and orders by it, so the client reviews the questions
-- in the order the Team Lead numbered them rather than by area. Unnumbered
-- questions fall to the end instead of jumping to the front.
create or replace function get_controlling_doc_form_data(p_client_id uuid)
returns table (
  client_name  text,
  sponsor_name text,
  questions    jsonb
)
language plpgsql
security definer
set search_path = public
as $$
begin
  set local row_security = off;

  return query
    select
      c.name,
      (select edc.name from econ_dev_companies edc where edc.id = c.econ_dev_company_id),
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id', q.id,
            'research_area', q.research_area,
            'question_number', q.question_number,
            'question', q.question,
            'background', q.background,
            'ranking', q.ranking,
            'customer_notes', q.customer_notes,
            'sort_order', q.sort_order
          )
          order by q.question_number nulls last, q.research_area, q.sort_order
        )
        from client_research_questions q
        where q.client_id = c.id
          and coalesce(nullif(trim(q.question), ''), '') <> ''
      ), '[]'::jsonb)
    from clients c
    where c.id = p_client_id;
end;
$$;

grant usage on schema public to anon;
grant execute on function get_controlling_doc_form_data(uuid) to anon;

-- ---------- 4. the close-out Evaluation Sheet ----------
-- This one returns a bare text[], and evaluation_public.html keys the CEO's
-- saved answers off the array index. Changing the shape to carry the number
-- as its own field would mean reworking that page's saved-state format, and
-- the number would then have to be re-rendered in three places there. The
-- number is prefixed into the text instead: it reads the way a numbered
-- question should on the survey, and it is stored that way in the response
-- record, which is what makes "question 3 was rated Very Useful" answerable
-- later. Questions now come out in numbered order rather than by area.
create or replace function get_evaluation_form_data(p_client_id uuid)
returns table (
  client_name  text,
  sponsor_name text,
  questions    text[]
)
language plpgsql
security definer
set search_path = public
as $$
begin
  set local row_security = off;

  return query
    select
      c.name,
      (select edc.name from econ_dev_companies edc where edc.id = c.econ_dev_company_id),
      coalesce((
        select array_agg(
          case
            when q.question_number is null then btrim(q.question)
            else q.question_number || '. ' || btrim(q.question)
          end
          order by q.question_number nulls last, q.research_area, q.sort_order
        )
        from client_research_questions q
        where q.client_id = c.id
          and coalesce(nullif(trim(q.question), ''), '') <> ''
      ), '{}'::text[])
    from clients c
    where c.id = p_client_id;
end;
$$;

grant execute on function get_evaluation_form_data(uuid) to anon;

-- ---------- 5. the client dashboard ----------
-- 123_show_research_questions.sql's body, with two changes inside the
-- research_areas block: each question object now carries 'number', and the
-- questions within an area are ordered by it. Everything else, including the
-- finalized-snapshot branch, is byte-for-byte 123.
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
        -- { number, question, documents } entries -- the questions
        -- (documents: []) when this engagement opts in, then the single
        -- trailing entry (question: null) that carries the area's
        -- client-facing documents. With the switch off the questions array is
        -- empty and this collapses to exactly the payload 115 produced.
        coalesce((
          select jsonb_object_agg(area, payload)
          from (
            select rat.area::text as area,
              (
                case when v_client.show_research_questions then coalesce((
                  select jsonb_agg(
                    jsonb_build_object(
                      'number', q.question_number,
                      'question', q.question,
                      'documents', '[]'::jsonb
                    )
                    order by q.question_number nulls last, q.sort_order asc, q.created_at asc, q.id
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
