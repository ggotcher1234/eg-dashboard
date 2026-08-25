-- 079_evaluation_form_data.sql
--
-- Depends on 033_research_questions.sql (client_research_questions,
-- research_area_type), 021_public_view_full_bundle.sql (the anon-grant
-- pattern this copies).
--
-- Greg (8/25/26): after generating a per-client evaluation link twice and
-- confirming it still rendered as raw HTML text instead of a form -- even
-- after fixing the upload code once already -- the real problem was the
-- architecture: a pre-baked .html file uploaded to Supabase Storage's
-- public bucket, whose Content-Type the browser kept getting wrong no
-- matter what the upload call passed. Storage was never a reliable way to
-- serve a live HTML page.
--
-- The fix: stop baking/uploading a file at all. evaluation_public.html
-- (a real page on the same Netlify site as everything else, so it always
-- renders correctly -- same guarantee client_public.html already has) now
-- takes a plain ?client=<id> query param and fetches the client's name,
-- sponsor program name, and research questions live, every time the CEO
-- opens the link. That also means the link never goes stale when
-- questions change -- there's no "Regenerate" step anymore.
--
-- This RPC is that fetch. No session/login -- a CEO clicking the link has
-- neither -- so it's security definer + row_security off + granted to
-- anon, same no-session pattern as get_client_public_view() (021).
--
-- Safe to re-run.

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
        select array_agg(q.question order by q.research_area, q.sort_order)
        from client_research_questions q
        where q.client_id = c.id
          and coalesce(nullif(trim(q.question), ''), '') <> ''
      ), '{}'::text[])
    from clients c
    where c.id = p_client_id;
end;
$$;

grant usage on schema public to anon;
grant execute on function get_evaluation_form_data(uuid) to anon;
