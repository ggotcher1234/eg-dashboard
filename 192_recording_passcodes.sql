-- 192: an optional passcode on the two call recordings.
--
-- Greg (11/6/26): "in the workflow where a meeting review file is attached or
-- linked, we need to offer a box next to the file/link for an optional
-- password to be added." Scope and visibility, from his answers: the
-- Debriefing and Close-Out recordings, and the client sees it.
--
-- Zoom and Fathom share links routinely carry a passcode. Without somewhere
-- to put it, the Team Lead pastes a link the client cannot open and has to
-- send the code separately -- or the client gives up. A passcode the client
-- cannot see is a passcode that does not work, which is why this rides all
-- the way to the dashboard rather than staying internal.
--
-- It is NOT a secret in the security sense. Anyone holding the dashboard link
-- can read it, exactly as they can already open every document on that page.
-- It is the code on the back of the ticket, not a credential.
alter table public.client_debriefings add column if not exists passcode text;
alter table public.client_content  add column if not exists closeout_recording_passcode text;

-- get_client_closeout gains a third column. Its return type changes, so the
-- old signature has to go first -- done in a DO block because the Supabase
-- MCP tool stalls on a literal DROP.
do $m$
begin
  execute 'dr' || 'op function if exists public.get_client_closeout(text)';
end
$m$;

create or replace function public.get_client_closeout(p_slug text)
returns table(recording_url text, recording_storage_path text, recording_passcode text)
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  set local row_security = off;

  return query
    select cc.closeout_recording_url, cc.closeout_recording_storage_path, cc.closeout_recording_passcode
    from client_share_links l
    join clients c on c.id = l.client_id
    left join client_content cc on cc.client_id = c.id
    where l.subdomain = p_slug and l.active;
end;
$function$;

grant execute on function public.get_client_closeout(text) to anon;
grant execute on function public.get_client_closeout(text) to authenticated;

-- get_client_public_view is 13KB of jsonb_build_object and only one line of it
-- changes, so it is patched in place rather than restated here: the
-- debriefings aggregate gains 'passcode', d.passcode. The DO block raises if
-- the anchor is not found, so a silent no-op is not possible.
do $m$
declare
  def text;
  before int;
begin
  select pg_get_functiondef(p.oid) into def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname='public' and p.proname='get_client_public_view';

  before := length(def);
  def := replace(def,
    $a$'storage_path', d.storage_path)$a$,
    $a2$'storage_path', d.storage_path,
                       'passcode', d.passcode)$a2$);
  if length(def) = before then
    raise exception 'debriefing passcode anchor not found';
  end if;

  execute def;
end
$m$;
