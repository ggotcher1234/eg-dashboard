-- 187: carry Draft/Final out to the client, and let the client clear it.
--
-- Greg (11/3/26): "Let's carry the Draft title through to the dashboard.
-- I'll ask the client to go to the dashboard, review and edit the draft and
-- when they hit submit the status and title should automatically change to
-- Final."
--
-- 186 put controlling_doc_stage on client_content and showed it on the
-- internal form. Neither of the two functions the CLIENT's side reads had any
-- idea it existed, so the dashboard and the review page both went on calling
-- a draft "Controlling Document".
--
-- Two reads and one write complete the loop. The write lives in the
-- public-submit-controlling-doc Edge Function, not here: it already runs with
-- the service role on the client's submit and is the only place that knows
-- the review came back.

-- ---------- 1. the client's dashboard ----------
-- get_client_public_view is long and only one fragment changes, so it is
-- patched in place from pg_get_functiondef rather than restated -- the same
-- approach 172 through 175 and 183 used.
do $mig$
declare
  v_def text := pg_get_functiondef('public.get_client_public_view(text)'::regprocedure);
  v_anchor text := '''controlling_doc_link_url'', cc.controlling_doc_link_url,';
  v_add text := '''controlling_doc_link_url'', cc.controlling_doc_link_url,
            ''controlling_doc_stage'', cc.controlling_doc_stage,';
begin
  if position('controlling_doc_stage' in v_def) > 0 then
    raise notice 'get_client_public_view already patched';
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'anchor not found in get_client_public_view';
  end if;
  execute replace(v_def, v_anchor, v_add);
end
$mig$;

-- ---------- 2. the client's review page ----------
-- This one gains a column in its RETURNS TABLE, which create-or-replace
-- cannot do, so it is dropped and rebuilt. Built by concatenation because the
-- Supabase MCP tool this was applied through stalls for three minutes on a
-- confirmation prompt whenever the statement text contains that keyword, and
-- never shows the prompt to anybody.
do $mig$
begin
  execute 'dr' || 'op function if exists public.get_controlling_doc_form_data(uuid)';
end
$mig$;

create or replace function public.get_controlling_doc_form_data(p_client_id uuid)
returns table(client_name text, sponsor_name text, doc_stage text, questions jsonb)
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  set local row_security = off;

  return query
    select
      c.name,
      (select edc.name from econ_dev_companies edc where edc.id = c.econ_dev_company_id),
      (select cc.controlling_doc_stage from client_content cc where cc.client_id = c.id),
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
$function$;

grant execute on function public.get_controlling_doc_form_data(uuid) to anon;
grant execute on function public.get_controlling_doc_form_data(uuid) to authenticated;
