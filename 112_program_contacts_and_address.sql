-- 112_program_contacts_and_address.sql
--
-- Depends on 089_program_contact_structured_fields.sql (which added the
-- `category` enum column to econ_dev_partner_contacts) and
-- 085_program_physical_address.sql (econ_dev_companies.physical_address).
--
-- Greg (9/6/26), rebuilding the Program form against Chris's "EG PROGRAMS
-- CONTACT INFO" doc: "I need a line for the Program Name, Abbreviation, and
-- Address (Street/POB, City, State, Zip, Phone) Then I need a list of the
-- people, (Name, Title, Email, Phone) Then a selection box for each person
-- that includes Primary Contact, Program Administrator, Program Finance,
-- Contract Signer, and CC List. Under that a List of Regional Directors,
-- (Region Name, Director Name, Title, Email, and Phone)" -- and: "a name can
-- have multiple functions and be on the cc list."
--
-- WHY ROLES STOP BEING A CATEGORY
-- `category` is a single enum per row, so a person can hold exactly one role.
-- The source doc disproves that on its first Program: Terrell Ellis is listed
-- under Primary Contact, under Program Administrator, AND under Program
-- Finance. As one enum he needs three rows -- his email and phone stored three
-- times, free to drift apart, and three rows to fix when he changes jobs.
--
-- So roles become independent booleans: one row per human, any combination of
-- roles ticked. include_on_cc is one more flag alongside them rather than a
-- special case.
--
-- `category` is NOT dropped. Nothing reads it after this, the booleans are
-- backfilled from it below, and leaving it means this migration is revertible
-- and no existing row loses information. Same for
-- econ_dev_companies.physical_address under the address split.
--
-- Safe to re-run: every add is IF NOT EXISTS, and every backfill only writes
-- where the new column is still unset.

-- ---------------------------------------------------------------------------
-- Contacts: roles as flags
-- ---------------------------------------------------------------------------

alter table econ_dev_partner_contacts add column if not exists include_on_cc            boolean not null default false;
alter table econ_dev_partner_contacts add column if not exists is_primary_contact       boolean not null default false;
alter table econ_dev_partner_contacts add column if not exists is_program_administrator boolean not null default false;
alter table econ_dev_partner_contacts add column if not exists is_program_finance       boolean not null default false;
alter table econ_dev_partner_contacts add column if not exists is_contract_signer       boolean not null default false;
alter table econ_dev_partner_contacts add column if not exists is_regional_director     boolean not null default false;

-- Region name sits alongside the person for Regional Directors -- in the doc
-- each one is headed by their organisation ("Boone County Community and
-- Economic Development Authority") before the person's own name and title.
-- Null for everyone else.
alter table econ_dev_partner_contacts add column if not exists region text;

comment on column econ_dev_partner_contacts.include_on_cc is
  'Copied on Program correspondence. Independent of every role flag.';
comment on column econ_dev_partner_contacts.region is
  'Organisation / region name, for is_regional_director rows. Null otherwise.';

-- Backfill the flags from the single role each row carries today. A cc_list
-- row becomes a CC-flagged contact with no role -- which is exactly what it
-- was, a person to copy rather than a person with a job.
update econ_dev_partner_contacts
   set is_contract_signer       = (category = 'contract_signer'),
       is_program_administrator = (category = 'program_administrator'),
       is_program_finance       = (category = 'program_finance'),
       include_on_cc            = include_on_cc or (category = 'cc_list')
 where not (is_contract_signer or is_program_administrator or is_program_finance or include_on_cc);

-- No primary_contact backfill on purpose. Until now the Programs list inferred
-- one ("first CC-flagged contact in sort order"), which is an ordering
-- accident, not a stated fact -- promoting a guess into a real column would
-- bake it in. Primary Contact starts unticked everywhere and gets set as each
-- Program is touched.

create index if not exists econ_dev_partner_contacts_cc_idx
  on econ_dev_partner_contacts (partner_id, include_on_cc)
  where include_on_cc;

create index if not exists econ_dev_partner_contacts_regional_idx
  on econ_dev_partner_contacts (partner_id, is_regional_director)
  where is_regional_director;

-- ---------------------------------------------------------------------------
-- Programs: address split into real fields, plus a phone
-- ---------------------------------------------------------------------------

alter table econ_dev_companies add column if not exists address_street text;
alter table econ_dev_companies add column if not exists address_city   text;
alter table econ_dev_companies add column if not exists address_state  text;
alter table econ_dev_companies add column if not exists address_zip    text;
alter table econ_dev_companies add column if not exists phone          text;

-- The whole existing string goes into street; City/State/Zip start empty. No
-- comma-splitting or state/ZIP pattern-matching -- that works on the tidy rows
-- and quietly mangles the rest, and you can't tell which is which without
-- checking every Program by hand. Same call 089 made with the old free-form
-- contact blocks.
update econ_dev_companies
   set address_street = physical_address
 where address_street is null
   and physical_address is not null
   and btrim(physical_address) <> '';
