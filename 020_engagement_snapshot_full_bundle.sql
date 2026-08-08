-- 020_engagement_snapshot_full_bundle.sql
--
-- Depends on 019_client_profile_content.sql.
--
-- Extends engagement_snapshots to freeze the full client-facing content
-- bundle (company profile, workflow doc links, contacts, competitors, top
-- customers, resource vault, next steps, team, research documents by area)
-- -- not just research_areas/documents like before -- so a finalized/closed
-- client still shows an accurate, complete, frozen copy on its public page.
-- Rewrites finalize_client() to populate all of it.
--
-- Safe to re-run.

alter table engagement_snapshots add column if not exists company        jsonb not null default '{}'::jsonb;
alter table engagement_snapshots add column if not exists workflow       jsonb not null default '{}'::jsonb;
alter table engagement_snapshots add column if not exists contacts      jsonb not null default '[]'::jsonb;
alter table engagement_snapshots add column if not exists competitors    jsonb not null default '[]'::jsonb;
alter table engagement_snapshots add column if not exists top_customers  jsonb not null default '[]'::jsonb;
alter table engagement_snapshots add column if not exists resource_vault jsonb not null default '[]'::jsonb;
alter table engagement_snapshots add column if not exists next_steps     jsonb not null default '[]'::jsonb;
alter table engagement_snapshots add column if not exists team          jsonb not null default '[]'::jsonb;

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

  -- research_areas: an array of client-facing documents tagged to each of
  -- the four areas (Section 4.3) -- the actual content model per Greg's
  -- real workflow (consultants' files, not freeform Q&A text).
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
      select jsonb_agg(jsonb_build_object('title', r.title, 'url', r.url) order by r.sort_order)
      from client_resource_vault_items r where r.client_id = p_client_id
    ), '[]'::jsonb),
    coalesce((
      select jsonb_agg(jsonb_build_object('description', n.description, 'completed', n.completed) order by n.sort_order)
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
