-- 085_program_physical_address.sql
--
-- Greg (8/27/26): "Add address field" to the EG Programs list (a plain
-- mailing/location address column, shown right in the table like Clients
-- and the Roster already do).
--
-- econ_dev_companies.address already exists, but 083's comment nails why
-- it can't be reused here: that column was repurposed back in 068 to hold
-- the whole "Program Finance" freeform contact block (name/title, org,
-- mailing address, email, phone -- everything needed to send an invoice),
-- not a short physical address. Several Programs already have real data
-- saved in it under that meaning via Chris's CSV import, so overloading
-- it again for a different purpose would corrupt that data. This adds a
-- new, genuinely separate column for the Program's own physical address --
-- single free-text line, same simple style as clients.address, not split
-- into street/city/state.
--
-- Safe to re-run.

alter table econ_dev_companies add column if not exists physical_address text;
