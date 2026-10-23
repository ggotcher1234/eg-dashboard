-- 175_research_summary_and_mandatory_questions.sql
--
-- Greg (10/23/26): "We want to make the questions mandatory now but in a
-- dropdown or popup. click to read the question style. we want to add a
-- 'Summary' box in each task assignment so the specialist can write a
-- paragraph summary about the research. That summary should also be on the
-- dashboard with a dropdown or popup to read it. then the files for each
-- task should show up below the question and summary boxes as they do now."
--
-- Three changes here, one in the column and two in the view.
--
-- 1. client_research_questions.summary -- the specialist's paragraph,
--    written on the Research page, read by the client on their dashboard.
--
-- 2. Questions are no longer gated on clients.show_research_questions. It
--    was off for six of the nine live engagements, so their clients had
--    never seen a question; they all show now. The column stays in the
--    table but nothing reads it any more, and the tickbox that set it is
--    gone from the Research page.
--
-- 3. Each question carries its OWN client-facing documents, so the
--    dashboard can render question -> summary -> files per question
--    instead of one list of questions above one pooled list of files. The
--    trailing entry (question: null) keeps only documents tied to no
--    question, so nothing is listed twice. Every client-facing document on
--    every live engagement already has a question_id, so in practice that
--    entry is empty.
--
-- As in 172-174, the view is rewritten from its own live definition rather
-- than retyped, with each replace checked.

alter table client_research_questions add column if not exists summary text;

comment on column client_research_questions.summary is
  'Greg (10/23/26): "add a Summary box in each task assignment so the specialist can write a paragraph summary about the research." Written by the specialist on the Research page; shown to the client on their dashboard, under the question and above that question''s files, behind a click-to-read row. Hidden from the client while empty.';

do $$
declare
  v_def text := pg_get_functiondef('public.get_client_public_view(text)'::regprocedure);
  v_new text;
  v_old text;
begin
  v_old :=
    '                case when v_client.show_research_questions then coalesce((' || chr(10) ||
    '                  select jsonb_agg(' || chr(10) ||
    '                    jsonb_build_object(' || chr(10) ||
    '                      ''number'', q.question_number,' || chr(10) ||
    '                      ''question'', q.question, ''person'', (select pu.full_name from users pu where pu.id = q.assigned_user_id),' || chr(10) ||
    '                      ''documents'', ''[]''::jsonb' || chr(10) ||
    '                    )' || chr(10) ||
    '                    order by q.question_number nulls last, q.sort_order asc, q.created_at asc, q.id' || chr(10) ||
    '                  )' || chr(10) ||
    '                  from client_research_questions q' || chr(10) ||
    '                  where q.client_id = v_client.id' || chr(10) ||
    '                    and q.research_area = rat.area' || chr(10) ||
    '                    -- a blank question row is a half-typed one, not content' || chr(10) ||
    '                    and coalesce(btrim(q.question), '''') <> ''''' || chr(10) ||
    '                ), ''[]''::jsonb) else ''[]''::jsonb end';

  if position(v_old in v_def) = 0 then
    raise exception 'question block not found -- definition has moved';
  end if;

  v_new := replace(v_def, v_old,
    '                coalesce((' || chr(10) ||
    '                  select jsonb_agg(' || chr(10) ||
    '                    jsonb_build_object(' || chr(10) ||
    '                      ''number'', q.question_number,' || chr(10) ||
    '                      ''question'', q.question,' || chr(10) ||
    '                      ''summary'', nullif(btrim(coalesce(q.summary, '''')), ''''),' || chr(10) ||
    '                      ''person'', (select pu.full_name from users pu where pu.id = q.assigned_user_id),' || chr(10) ||
    '                      ''documents'', coalesce((' || chr(10) ||
    '                        select jsonb_agg(' || chr(10) ||
    '                          jsonb_build_object(''file_name'', d.file_name, ''display_name'', d.display_name, ''storage_path'', d.storage_path, ''url'', d.url)' || chr(10) ||
    '                          order by d.sort_order asc nulls last, d.uploaded_at desc, d.id' || chr(10) ||
    '                        )' || chr(10) ||
    '                        from documents d' || chr(10) ||
    '                        where d.question_id = q.id and d.visibility = ''client_facing''' || chr(10) ||
    '                      ), ''[]''::jsonb)' || chr(10) ||
    '                    )' || chr(10) ||
    '                    order by q.question_number nulls last, q.sort_order asc, q.created_at asc, q.id' || chr(10) ||
    '                  )' || chr(10) ||
    '                  from client_research_questions q' || chr(10) ||
    '                  where q.client_id = v_client.id' || chr(10) ||
    '                    and q.research_area = rat.area' || chr(10) ||
    '                    -- a blank question row is a half-typed one, not content' || chr(10) ||
    '                    and coalesce(btrim(q.question), '''') <> ''''' || chr(10) ||
    '                ), ''[]''::jsonb)');

  v_def := v_new;
  v_new := replace(v_def,
    '                  where d.client_id = v_client.id and d.research_area = rat.area and d.visibility = ''client_facing''',
    '                  where d.client_id = v_client.id and d.research_area = rat.area and d.visibility = ''client_facing''' || chr(10) ||
    '                    and d.question_id is null');
  if v_new = v_def then raise exception 'area-document filter not found'; end if;

  execute v_new;
end $$;
