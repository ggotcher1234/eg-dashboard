-- 149_evaluation_response_pdf_url.sql (10/6/26)   [APPLIED]
--
-- Greg: "we need to make sure the admins are copied when an Evaluation Sheet
-- is submitted. not just a bell notification... I'd like to get an email
-- saying it was submitted, it is attached to the email and available to
-- download on the Clippard Dashboard." Recipients confirmed as the
-- engagement's Team Lead plus all three admins.
--
-- The PDF the function generates on submit lives in the already-public
-- client-evaluations bucket; its URL hangs off the response row, so the row
-- owns its own document.
--
-- Deliberately NOT client_content.closeout_survey_storage_path: that column
-- feeds the dashboard's Evaluation Sheet step and a file there wins over the
-- submitted-response branch, so writing the PDF to it would hijack the step
-- (which opens the live, filled-in sheet) and replace it with a static file.
-- The dashboard gets a separate small download link instead.
alter table client_evaluation_responses
  add column if not exists pdf_url text;

-- Targeted patch of the live function, same reason as 142/145: this one is
-- ~200 lines and a dozen migrations have edited it; retyping it is how a
-- body silently reverts to an older version.
do $outer$
declare
  src    text;
  needle text := '''evaluation_submitted_at'', (';
  addition text := '''evaluation_pdf_url'', (
              select r.pdf_url from client_evaluation_responses r
               where r.client_id = v_client.id
               order by r.submitted_at desc limit 1
            ),
            ';
begin
  select pg_get_functiondef(p.oid) into src
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'get_client_public_view';

  if src is null then raise exception 'get_client_public_view not found'; end if;
  if position('evaluation_pdf_url' in src) > 0 then
    raise notice 'evaluation_pdf_url already present'; return;
  end if;
  if position(needle in src) = 0 then
    raise exception 'anchor not found in function body';
  end if;

  src := replace(src, needle, addition || needle);
  execute src;
end
$outer$;
