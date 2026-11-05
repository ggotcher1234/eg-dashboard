-- 188: a read-only Discovery Document a candidate researcher can open.
--
-- Greg (11/5/26): "typically before we assign a researcher we request their
-- availability and how many hours they would need. we typically share the
-- Discovery Document and the Controlling document with them so they can make
-- their own assessment."
--
-- Mary Ellen Bates found the hole first: sent both links, she could open the
-- Controlling Document and not the Discovery Document. Not a bug -- the
-- Controlling Document's link goes through a security-definer function and
-- needs no account (it is built to be sent to the client), while the
-- Discovery Document only existed as an internal page behind sign-in AND an
-- assignment on that engagement. So the only way to let a candidate read it
-- was to assign them, which makes somebody a full team member -- on hours
-- reports, in assignee dropdowns -- before they have said yes.
--
-- Same access model as the Controlling Document, which is what Greg picked:
-- unguessable URL, no account, no expiry.
--
-- WHAT IS DELIBERATELY NOT IN HERE
-- The Discovery form holds the client's contacts and the CC list -- names,
-- emails, phone numbers. A candidate sizing up the work does not need them,
-- and this link can be forwarded, so the function returns the shape of the
-- engagement and nothing that identifies a person at the client beyond the
-- first names already typed into the participants line. Add columns here and
-- they are public; that is the whole reason this is an explicit column list
-- rather than a select *.
alter table public.client_content
  add column if not exists discovery_doc_link_url text;

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
  attachment_url text
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
      -- The call recording filed at the bottom of the Discovery form (183's
      -- sibling fix gave it its own column). Watching the call is the
      -- fastest way for a researcher to judge the work.
      nullif(btrim(cc.discovery_notes_url), '')
    from clients c
    left join client_content cc on cc.client_id = c.id
    where c.id = p_client_id;
end;
$fn$;

grant execute on function public.get_discovery_doc_public(uuid) to anon;
grant execute on function public.get_discovery_doc_public(uuid) to authenticated;
