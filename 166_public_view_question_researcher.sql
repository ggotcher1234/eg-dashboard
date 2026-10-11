-- 166: the client dashboard says who researched each question.
--
-- Greg (10/11/26): "the 'research by' name is not showing up on the dashboard
-- even though the researchers have been added to the controlling document and
-- the hours document." The assignment was being saved (161 put it on every
-- Controlling Document question, and the Evaluation Sheet reads it), but the
-- client-facing view never carried it out, so the dashboard had nothing to
-- print.
--
-- get_client_public_view is long and only one line of it changes, so this
-- re-points the existing definition rather than retyping it: read the
-- function back, add 'person' to the per-question object, run the result.
-- The guard makes a second run a no-op.

do $do$
declare src text;
begin
  select pg_get_functiondef(p.oid) into src
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'get_client_public_view';

  if position($g$'person',$g$ in src) > 0 then
    raise notice 'get_client_public_view already carries the researcher; nothing to do';
    return;
  end if;

  src := replace(src,
    $m$'question', q.question,$m$,
    $m$'question', q.question, 'person', (select pu.full_name from users pu where pu.id = q.assigned_user_id),$m$);

  execute src;
end
$do$;
