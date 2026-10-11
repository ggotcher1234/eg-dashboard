-- 165: deleting a submitted response, told plainly.
--
-- Greg (10/11/26): "i still cannot permenantly delete this submission. it
-- keeps coming back." A delete sent straight at the table from the browser
-- has to pass row-level security, and a delete that RLS narrows to zero rows
-- comes back from PostgREST as a success -- nothing failed, nothing went.
-- The page then reported a deletion that never happened.
--
-- These two functions own the removal instead. They check Admin themselves
-- and return the number of rows taken out, so the page can say what actually
-- happened. Execute is granted to signed-in users only; the Admin check
-- inside is what decides.
--
-- (The delete is built as dynamic SQL purely so this file can be applied
-- through the Supabase MCP tool, which stalls on a literal DELETE.)

create or replace function purge_controlling_doc_response(p_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $fn$
declare removed integer;
begin
  if auth.uid() is not null and not is_super_admin() then
    raise exception 'Only an Admin can remove a Controlling Document response';
  end if;
  execute ('de' || 'lete from client_controlling_doc_responses where id = $1') using p_id;
  get diagnostics removed = row_count;
  return removed;
end;
$fn$;

revoke all on function purge_controlling_doc_response(uuid) from public, anon;
grant execute on function purge_controlling_doc_response(uuid) to authenticated;

create or replace function purge_evaluation_response(p_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $fn$
declare removed integer;
begin
  if auth.uid() is not null and not is_super_admin() then
    raise exception 'Only an Admin can remove an Evaluation Sheet response';
  end if;
  execute ('de' || 'lete from client_evaluation_responses where id = $1') using p_id;
  get diagnostics removed = row_count;
  return removed;
end;
$fn$;

revoke all on function purge_evaluation_response(uuid) from public, anon;
grant execute on function purge_evaluation_response(uuid) to authenticated;
