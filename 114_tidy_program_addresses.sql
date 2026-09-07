-- 114_tidy_program_addresses.sql
--
-- Depends on 112 and 113. Fixes a collision between the two of them.
--
-- Greg (9/7/26), looking at the Programs list after running the import:
-- "3003 Dale Earnhardt Blvd #2, Kannapolis, NC 28083, Kannapolis, NC 28083".
--
-- WHAT WENT WRONG
-- 112 split the address into street/city/state/zip and, having no way to
-- parse the old free-form `physical_address` safely, put the WHOLE string in
-- address_street and left the other three empty -- deliberately, because
-- comma-splitting works on the tidy rows and quietly mangles the rest.
-- 113 then filled city/state/zip from Chris's doc, exactly as intended,
-- because they were empty. Both steps were right on their own; together they
-- state the city and the ZIP twice.
--
-- This trims the tail off address_street ONLY where it repeats what is now in
-- the structured fields, matching loosely enough to catch the real spacing in
-- these rows ("Kannapolis, NC  28083", "Kannapolis NC 28083") and refusing to
-- do anything at all when it can't find that exact tail. A street that never
-- carried a city is left alone; so is one whose city doesn't match.
--
-- Safe to re-run: a second pass finds nothing left to trim.

update econ_dev_companies
   set address_street = btrim(
         regexp_replace(
           address_street,
           '[\s,]*' || regexp_replace(address_city, '([\\.^$*+?()\[\]{}|])', '\\\1', 'g')
                    || '[\s,]*' || regexp_replace(coalesce(address_state, ''), '([\\.^$*+?()\[\]{}|])', '\\\1', 'g')
                    || '\.?[\s,]*' || coalesce(address_zip, '') || '\s*$',
           '', 'i'),
         ' ,')
 where coalesce(btrim(address_city), '') <> ''
   and coalesce(btrim(address_zip),  '') <> ''
   and address_street is not null
   and address_street ~* ('[\s,]' || regexp_replace(address_city, '([\\.^$*+?()\[\]{}|])', '\\\1', 'g')
                          || '[\s,]*' || regexp_replace(coalesce(address_state, ''), '([\\.^$*+?()\[\]{}|])', '\\\1', 'g')
                          || '\.?[\s,]*' || coalesce(address_zip, '') || '\s*$');

-- The same tail without the ZIP -- "…, Annapolis, MD" with the ZIP only in its
-- own column.
update econ_dev_companies
   set address_street = btrim(
         regexp_replace(
           address_street,
           '[\s,]+' || regexp_replace(address_city, '([\\.^$*+?()\[\]{}|])', '\\\1', 'g')
                    || '[\s,]+' || regexp_replace(coalesce(address_state, ''), '([\\.^$*+?()\[\]{}|])', '\\\1', 'g')
                    || '\.?\s*$',
           '', 'i'),
         ' ,')
 where coalesce(btrim(address_city),  '') <> ''
   and coalesce(btrim(address_state), '') <> ''
   and address_street is not null
   and address_street ~* ('[\s,]+' || regexp_replace(address_city, '([\\.^$*+?()\[\]{}|])', '\\\1', 'g')
                          || '[\s,]+' || regexp_replace(coalesce(address_state, ''), '([\\.^$*+?()\[\]{}|])', '\\\1', 'g')
                          || '\.?\s*$');

-- What's left, for eyeballing.
select code, name, address_street, address_city, address_state, address_zip
  from econ_dev_companies
 where coalesce(btrim(address_street), '') <> ''
 order by name;

-- ---------------------------------------------------------------------------
-- Possible duplicate Programs
-- ---------------------------------------------------------------------------
-- The import creates a Program when it can't find a match, and it matches on a
-- phrase from the doc's name -- so a Program you call something else entirely
-- ("Empower Rural Iowa" for the doc's "OPPORTUNITY SQUARED (AREA 15 IOWA)")
-- would not have matched and now exists twice.
--
-- This finds nothing on its own; it just lists Programs that share a contact
-- email with another Program, which is what a duplicate looks like from the
-- data. Nothing here is deleted -- merge by hand, or tell me which pairs are
-- really one Program.
select
  string_agg(distinct c.name || '  [' || c.code || ']', '   <->  ' order by c.name || '  [' || c.code || ']')
                                                as "these two Programs...",
  lower(btrim(k.email))                         as "...share this contact",
  count(distinct c.id)                          as programs
from econ_dev_partner_contacts k
join econ_dev_companies c on c.id = k.partner_id
where coalesce(btrim(k.email), '') <> ''
group by lower(btrim(k.email))
having count(distinct c.id) > 1
order by 1;
