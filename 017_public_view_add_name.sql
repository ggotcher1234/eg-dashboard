-- 017_public_view_add_name.sql
--
-- The real client-facing dashboard page (client_public.html) needs the
-- company's own name to put in the page header — get_client_public_view()
-- didn't return it before (only client_status, research_areas, documents).
-- A client's own company name is not sensitive relative to that client, so
-- this is safe to add. Everything else about the function (Section 4.3's
-- internal/external split) is unchanged.
--
-- Changing a function's RETURNS TABLE column list isn't allowed via a plain
-- CREATE OR REPLACE (same lesson as migration 011 with parameter lists) —
-- the old signature has to be dropped first, and the anon grant re-applied
-- afterward since DROP clears it.
--
-- Safe to re-run.

drop function if exists get_client_public_view(text);

create or replace function get_client_public_view(p_slug text)
returns table (
  client_status  client_status,
  client_name    text,
  research_areas jsonb,
  documents      jsonb
)
language plpgsql
security definer
set search_path = public
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
      select v_client.status, v_client.name, s.research_areas, s.documents
      from engagement_snapshots s
      where s.client_id = v_client.id
      order by s.created_at desc
      limit 1;
  else
    return query
      select
        v_client.status,
        v_client.name,
        coalesce(cc.research_areas, '{}'::jsonb),
        coalesce(
          jsonb_agg(jsonb_build_object('file_name', d.file_name, 'storage_path', d.storage_path))
            filter (where d.visibility = 'client_facing'),
          '[]'::jsonb
        )
      from client_content cc
      left join documents d on d.client_id = v_client.id
      where cc.client_id = v_client.id
      group by v_client.status, cc.research_areas;
  end if;
end;
$$;

grant usage on schema public to anon;
grant execute on function get_client_public_view(text) to anon;
