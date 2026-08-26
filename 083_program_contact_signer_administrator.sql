-- 083_program_contact_signer_administrator.sql
--
-- Chris sent over a standing "EG Programs Contact Info" doc (6/25/26) that
-- Greg wants the EG Programs admin screen to match, using its exact 3-block
-- format per Program:
--   Contract Signer         (renamed by Chris from "Primary Contact")
--   Program Administrator
--   Program Finance
--
-- econ_dev_companies.address already IS the Program Finance block (freeform
-- text -- name/title, org, mailing address, email, phone; see 068's comment
-- and the "Program Finance" label already on that field in the Program
-- Detail popup) -- no change needed there. This adds the other two blocks
-- as the same kind of freeform text, so a Program with 8 Regional Directors
-- crammed into "Program Administrator" (e.g. Advantage Valley) can still be
-- pasted in as one block, same as Program Finance already handles.
--
-- Safe to re-run.

alter table econ_dev_companies add column if not exists contract_signer text;
alter table econ_dev_companies add column if not exists program_administrator text;
