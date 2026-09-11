-- 117_merge_primary_into_pa.sql
--
-- Depends on 112_program_contacts_and_address.sql, which created the role
-- flags.
--
-- Greg (9/11/26), settling the question left open by the Chris/Rita review:
-- "combine Primary and Admin into one and label it PA."
--
-- The review named three roles -- Signer, PA, Finance -- and the form had
-- four, the extra one being Primary Contact. It was never really a job title;
-- in practice the Program Administrator IS who you call first, so the two
-- said the same thing in two tickboxes and invited disagreement between them.
--
-- Anyone flagged Primary Contact becomes a Program Administrator. OR'd rather
-- than copied, so someone already marked both stays marked once. Nobody loses
-- a marking.
--
-- is_primary_contact is NOT dropped: the form stops offering it from today,
-- but leaving the column means this is revertible and no row silently loses
-- information. Dropping it is a separate migration once nobody misses it --
-- same call 112 made with `category`.
--
-- Safe to re-run: the second pass finds nothing left to merge.

update econ_dev_partner_contacts
   set is_program_administrator = true
 where is_primary_contact
   and not is_program_administrator;

-- What moved, for the record.
do $$
declare n int;
begin
  select count(*) into n from econ_dev_partner_contacts
   where is_primary_contact and is_program_administrator;
  raise notice '% contact(s) carry both flags; all of them now show as PA.', n;
end $$;
