-- 142_public_view_evaluation_form_url.sql   (10/6/26)
--
-- Greg: "make the client evaluation sheet available to open from the client
-- dashboard as soon as the controlling document is submitted. That way the
-- client can view it from their dashboard, fill it out and submit it. Only
-- after submission should it show the checkmark and link to the final
-- document."
--
-- Everything the dashboard needs was already in get_client_public_view's
-- payload except one thing: a URL for the live evaluation form.
-- client_content.evaluation_link_url holds it, but only once a Team Lead has
-- sent the evaluation email. Of the four engagements with a Controlling
-- Document in today, JLR Environmental has no saved link -- so keying off that
-- column alone would have handed the client this change is for a dead step.
--
-- So the payload gains evaluation_form_url: the saved link when there is one,
-- otherwise the same URL built from the client id. Relative, so it resolves
-- against whatever host is serving the dashboard.
--
-- This is written as a targeted patch of the LIVE definition rather than a
-- retyped CREATE OR REPLACE. That function is ~200 lines and has been edited
-- by 017, 021, 036, 063, 064, 104, 115, 123, 124 and 137; retyping it to add
-- one key is how a body silently reverts to an older migration's version.
-- Re-running this file is safe: it exits early if the key is already there.
do $outer$
declare
  src      text;
  needle   text := '''evaluation_link_url'', cc.evaluation_link_url,';
  addition text := '
            ''evaluation_form_url'', coalesce(
              nullif(btrim(cc.evaluation_link_url), ''''),
              ''evaluation_public.html?client='' || v_client.id::text
            ),';
begin
  select pg_get_functiondef(p.oid) into src
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'get_client_public_view';

  if src is null then
    raise exception 'get_client_public_view not found';
  end if;

  if position('evaluation_form_url' in src) > 0 then
    raise notice 'evaluation_form_url already present -- nothing to do';
    return;
  end if;

  if position(needle in src) = 0 then
    raise exception 'anchor not found in function body';
  end if;

  src := replace(src, needle, needle || addition);
  execute src;
end
$outer$;
