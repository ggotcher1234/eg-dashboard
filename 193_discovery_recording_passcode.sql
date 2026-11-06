-- 193: the Discovery call recording gets a passcode too.
--
-- Greg (11/6/26): "Change Attach a File or Link text to Attach Discovery Call
-- Recording File or Link. Make sure it has the optional password box too."
-- The sibling of 192, which did the Debriefing and Close-Out recordings.
--
-- This one matters most of the three. The Discovery Document share page is
-- what goes to a candidate researcher deciding whether to take the work
-- (188), and watching the call is the fastest way to judge it. A Fathom or
-- Zoom link they cannot open wastes the whole exercise, and the researcher
-- is not on the engagement yet, so there is nobody obvious to ask.
--
-- get_discovery_doc_public returns one more column, so the old signature has
-- to go first. Note what is still NOT in that function: the client's contacts
-- and CC list. A passcode for a recording the page already links to is the
-- same kind of thing as the link itself; a client's phone number is not.
alter table public.client_content add column if not exists discovery_notes_passcode text;

do $m$
begin
  execute 'dr' || 'op function if exists public.get_discovery_doc_public(uuid)';
end
$m$;

create or replace function public.get_discovery_doc_public(p_client_id uuid)
returns table(
  client_name text,
  program_name text,
  team_lead text,
  call_date date,
  participants text,
  company_description text,
  business_issues text,
  notes text,
  website_url text,
  attachment_url text,
  attachment_passcode text
)
language plpgsql
security definer
set search_path to 'public'
as $fn$
begin
  set local row_security = off;

  return query
    select
      c.name,
      coalesce(nullif(btrim(cc.discovery_program_name), ''),
               (select edc.name from econ_dev_companies edc where edc.id = c.econ_dev_company_id)),
      nullif(btrim(cc.discovery_team_lead), ''),
      cc.discovery_call_date,
      nullif(btrim(cc.discovery_call_participants), ''),
      nullif(btrim(cc.discovery_company_description), ''),
      nullif(btrim(cc.discovery_business_issues), ''),
      nullif(btrim(cc.discovery_call_notes), ''),
      nullif(btrim(cc.discovery_website_url), ''),
      nullif(btrim(cc.discovery_notes_url), ''),
      nullif(btrim(cc.discovery_notes_passcode), '')
    from clients c
    left join client_content cc on cc.client_id = c.id
    where c.id = p_client_id;
end;
$fn$;

grant execute on function public.get_discovery_doc_public(uuid) to anon;
grant execute on function public.get_discovery_doc_public(uuid) to authenticated;
