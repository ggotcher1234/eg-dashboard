-- 177_public_resource_nceg_titles.sql
--
-- Chris (10/23/26, via Greg): "Chris doesn't think the CEO will open the
-- dashboard and locate the files but if we could just create a simple link
-- in the email that opens each document from their own dashboard that
-- would work."
--
-- That link was built on 10/9/26 -- resource_link.html resolves /doc/faq
-- and /doc/what-to-expect and forwards to a freshly signed URL -- and it
-- has been broken since, in two places, which is why the Scheduling Letter
-- went back to saying "attached".
--
-- This is the database half. The allowlist matched the titles exactly as
-- they read on 10/9: "EG FAQs" and "EG ... What to Expect". The NCEG rename
-- on 10/16 made both rows "NCEG ...", so every lookup returned nothing and
-- the page showed its not-found card.
--
-- Matching on a contained pattern rather than a fixed prefix, so the next
-- rename does not silently break links already sitting in CEOs' inboxes.
-- The allowlist itself is unchanged: two keys answer, everything else
-- returns no rows, and the signed URL is minted for one object path in the
-- resource-templates folder.
--
-- The other half is a Netlify redirect for /doc/:key, which was never added
-- at all; it lives in netlify.toml.

create or replace function public.get_public_resource(p_key text)
returns table(title text, url text, storage_path text)
language sql stable security definer set search_path to 'public'
as $function$
  select t.title, t.url, t.storage_path
    from resource_vault_templates t
   where t.title ilike case lower(btrim(coalesce(p_key, '')))
           when 'faq'            then '%FAQ%'
           when 'what-to-expect' then '%What to Expect%'
           else null
         end
   order by t.created_at
   limit 1;
$function$;
