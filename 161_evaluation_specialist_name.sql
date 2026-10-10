-- 161: the Evaluation Sheet names who did each piece of research  [APPLIED]
--
-- Greg (10/10/26): "we want to include the specialist name with the
-- question - get from the Controlling Document. This will help the client
-- remember who did the research for that question."
--
-- The name is client_research_questions.assigned_user_id, set by the
-- Controlling Document's per-question Assigned Person picker (160/0726636)
-- and shared with the Research page's task list. One field, three screens.
--
-- A NEW FUNCTION rather than a changed one. Adding a column to a
-- RETURNS TABLE changes the return type, which Postgres accepts only after
-- the old function is dropped -- and for as long as that deploy took, every
-- evaluation link already sitting in a CEO's inbox would fail. So v2 stands
-- beside v1, evaluation_public.html moves over, and v1 can go later once
-- nothing calls it.
--
-- question_people is POSITIONAL: index i is who answered questions[i], ''
-- where nobody is assigned. Parallel arrays rather than the name folded
-- into the question text, because a submitted rating is matched back to its
-- question by that text (evaluation_public.html, fillFromSubmitted) --
-- changing the text would orphan every rating already on file.
create or replace function public.get_evaluation_form_data_v2(p_client_id uuid)
returns table(client_name text, sponsor_name text, questions text[], question_people text[])
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  set local row_security = off;

  return query
  with q as (
    select
      case
        when crq.question_number is null then btrim(crq.question)
        else crq.question_number || '. ' || btrim(crq.question)
      end as label,
      coalesce(u.full_name, '') as person,
      crq.question_number,
      crq.research_area,
      crq.sort_order
    from client_research_questions crq
    left join users u on u.id = crq.assigned_user_id
    where crq.client_id = p_client_id
      and coalesce(nullif(trim(crq.question), ''), '') <> ''
  )
  select
    c.name,
    (select edc.name from econ_dev_companies edc where edc.id = c.econ_dev_company_id),
    -- Both arrays come from ONE ordered pass over the same rows, so
    -- questions[i] and question_people[i] cannot drift apart.
    coalesce((select array_agg(q.label  order by q.question_number nulls last, q.research_area, q.sort_order) from q), '{}'::text[]),
    coalesce((select array_agg(q.person order by q.question_number nulls last, q.research_area, q.sort_order) from q), '{}'::text[])
  from clients c
  where c.id = p_client_id;
end;
$function$;

grant execute on function public.get_evaluation_form_data_v2(uuid) to anon, authenticated;
