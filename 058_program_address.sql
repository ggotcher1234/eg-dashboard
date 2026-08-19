-- 058_program_address.sql
--
-- Greg (8/19/26), simplifying the Programs page per Chris/Rita's list: "Add
-- address" to each EG Program. Plain free-text field (not split into
-- street/city/state like clients' addresses) -- Programs is being trimmed
-- down to the bare essentials (name, code, address, contacts), so this
-- stays a single line to match.
--
-- Safe to re-run.

alter table econ_dev_companies add column if not exists address text;
