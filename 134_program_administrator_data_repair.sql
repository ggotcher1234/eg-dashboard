-- 134: repair Program Administrator contact rows.  (APPLIED 9/30/26)
--
-- Rita approved a test application in Advantage Valley and was told the
-- Program had nobody marked Program Administrator. Adam Phillips WAS
-- marked. The Program carried two Adam Phillips rows: the one flagged
-- Program Administrator ("Program Admin.") had no email address, and the
-- one carrying aphillips@wceda.org was flagged cc. Everything downstream --
-- the approval letter, the engagement CC list, the application-link
-- composer -- needs the flag and the address on the same row.
--
-- None of the rows touched here were referenced by
-- client_team_partner_contacts, client_cc_contacts or
-- client_applications.program_contact_id (checked before running), so the
-- deletes took nothing with them.

-- ---- Advantage Valley (WV): one Adam, with his address ----
update econ_dev_partner_contacts
   set is_program_administrator = true
 where id = '9aaa5111-1a44-46fd-bf74-b4ca0f0b9068';   -- Adam Phillips <aphillips@wceda.org>

delete from econ_dev_partner_contacts
 where id = '6d9d1608-ff33-4b27-b009-a2dd29ab925b';   -- the emailless "Program Admin." duplicate

-- ---- Network Kansas (NK) ----
-- "Sradley@. networkKansas com" -- a stray period and two spaces where the
-- @ and the dot belong. Both of his colleagues on this Program use
-- @networkKansas.com, which is what settles the intended address.
update econ_dev_partner_contacts
   set email = 'sradley@networkKansas.com'
 where id = '16f5f2cb-b184-4403-a67c-136f4f312d89'
   and email = 'Sradley@. networkKansas com';

-- Kristi Pedersen was entered twice, identically.
delete from econ_dev_partner_contacts
 where id = 'e9218d74-ab7f-4d8f-a98d-33aaceba517b';

-- ---- Tri-Cities (Tricity) ----
-- An entirely blank row: no name, no title, no address, no flags.
delete from econ_dev_partner_contacts
 where id = '7c2b9aef-fbc6-4825-b374-484587f1ef3b';

-- ---- Standing check: Programs whose Program Administrator can't be written to ----
-- select p.name, p.code,
--        count(*) filter (where c.is_program_administrator) as pa_rows,
--        count(*) filter (where c.is_program_administrator
--                         and coalesce(trim(c.email),'') <> '') as pa_with_email
--   from econ_dev_companies p
--   left join econ_dev_partner_contacts c on c.partner_id = p.id and c.active is true
--  where p.active is true and p.archived is false
--  group by p.id, p.name, p.code
-- having count(*) filter (where c.is_program_administrator
--                         and coalesce(trim(c.email),'') <> '') <> 1
--  order by p.name;
