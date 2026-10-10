-- 162: the Close-Out recording  [APPLIED 10/10/26]
--
-- Greg (10/10/26): "this is a two part/two document category. the primary
-- category is going to be Close-Out and the submenu under close-out will be
-- evaluation sheet." On where the video comes from: "most TL's do a zoom
-- recording of the close out call. that unique link will be used so we will
-- need both Close-Out and Engagement sheet to open a window in the right
-- column where a file or link can be added that will also show up on the
-- client dashboard."
--
-- So the recording is per engagement, not one standard video: its own pair
-- of columns on client_content, filled the way Discovery, Controlling and
-- Debriefing already are (a link, or a file in client-documents).
--
-- NOT closeout_survey_*: those are the Evaluation Sheet's own attachment
-- slot, which the dashboard's Evaluation Sheet step still reads. Reusing
-- them for the recording would make one step mean two things.
alter table client_content
  add column if not exists closeout_recording_url text,
  add column if not exists closeout_recording_storage_path text;

comment on column client_content.closeout_recording_url is
  'Close-Out call recording (usually a Zoom link). Shown on the client dashboard as the top row of the Close-Out chevron.';
comment on column client_content.closeout_recording_storage_path is
  'Close-Out call recording uploaded as a file instead of a link; path in the client-documents bucket.';

-- The client dashboard is signed out, so it cannot read client_content. The
-- main public view (get_client_public_view) could carry these two values,
-- but that function is ~200 lines serving every section of the page, and for
-- a FINALIZED engagement it answers from engagement_snapshots -- which would
-- freeze out a recording attached after close-out, the very moment it gets
-- attached. This reads live either way.
create or replace function public.get_client_closeout(p_slug text)
returns table(recording_url text, recording_storage_path text)
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  set local row_security = off;

  return query
    select cc.closeout_recording_url, cc.closeout_recording_storage_path
    from client_share_links l
    join clients c on c.id = l.client_id
    left join client_content cc on cc.client_id = c.id
    where l.subdomain = p_slug and l.active;
end;
$function$;

grant execute on function public.get_client_closeout(text) to anon, authenticated;
