-- 184: the Controlling Document form gets its own attachment slot, and the
-- Discovery form's contacts reach the letters.
--
-- Greg (11/2/26): "also, do the same thing for the controlling document.
-- make sure the names/email addresses i added to the Discovery Document flow
-- through to the rest of the documents."
--
-- ---------- part one: the attachment slot ----------
-- The same trap 183's sibling fix found on Discovery. Submitting either form
-- points its Project Files row back at the form by writing a self-link into
-- <doc>_url. The "Attach a File or Link" slot at the bottom of the same form
-- wrote to those very columns, so filing anything there replaced the link to
-- the document it was filed inside -- and the row that should open the
-- filled-in form opened the attachment instead.
--
-- discovery_notes_* already existed and took that job on Discovery. The
-- Controlling Document had no equivalent, so here it is.
alter table public.client_content
  add column if not exists controlling_notes_url text,
  add column if not exists controlling_notes_storage_path text;

-- ---------- part two: contacts that go nowhere ----------
-- No schema change, a data repair. The Discovery form saved Company Contacts
-- and the CC List as text on client_content (discovery_company_contacts,
-- discovery_cc_list) and nothing but that page ever read them back, while
-- every letter the app drafts builds its To and CC from client_contacts and
-- client_cc_list. client_cc_list was empty on every engagement in the system.
--
-- On Chestnut Ridge that meant two people Greg had added -- the owner's wife
-- and the business manager -- were copied on nothing. The form writes to
-- these tables now; this brings across what was already typed.
insert into public.client_cc_list (client_id, name, title, email, sort_order)
select cc.client_id,
       btrim(e.value->>'name'),
       nullif(btrim(coalesce(e.value->>'title','')),''),
       nullif(btrim(coalesce(e.value->>'email','')),''),
       (e.ordinality)::int
  from public.client_content cc
  cross join lateral jsonb_array_elements(cc.discovery_cc_list::jsonb)
         with ordinality e(value, ordinality)
 where coalesce(btrim(cc.discovery_cc_list), '') not in ('', '[]')
   and not exists (select 1 from public.client_cc_list x where x.client_id = cc.client_id)
   and coalesce(nullif(btrim(e.value->>'name'), ''), nullif(btrim(e.value->>'email'), '')) is not null;

-- One of those rows came across as "<emoji> mkyoung@cityofsacramento.org",
-- pasted that way into the form. A mailto built from it is simply broken, so
-- the leading junk comes off here and the form strips it on the way in from
-- now on.
update public.client_cc_list
   set name  = btrim(name),
       title = nullif(btrim(coalesce(title, '')), ''),
       email = nullif(btrim(regexp_replace(coalesce(email, ''), '^[^[:alnum:]]+', '')), '')
 where name <> btrim(name)
    or email <> btrim(regexp_replace(coalesce(email, ''), '^[^[:alnum:]]+', ''));
