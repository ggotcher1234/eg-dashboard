-- 089_program_contact_structured_fields.sql
--
-- Depends on 039_econ_dev_partner_contacts.sql (econ_dev_partner_contacts,
-- the "CC List" contacts) and 083_program_contact_signer_administrator.sql
-- (the freeform contract_signer/program_administrator text columns on
-- econ_dev_companies; econ_dev_companies.address is the pre-existing
-- Program Finance freeform block from further back -- not to be confused
-- with physical_address, the separate literal street address added in 085).
--
-- Rita (8/28/26): wants named fields (Name, Title, Address, Email, Phone,
-- Notes) instead of one big freeform textarea for Contract Signer, Program
-- Administrator, and Program Finance -- the same shape the CC List
-- contacts already use, just with a category to tell the four contact
-- "buckets" for a Program apart, plus two fields (address, notes) those
-- buckets need that the CC List didn't.
--
-- This does NOT delete or touch econ_dev_companies.contract_signer,
-- program_administrator, or address (Program Finance) -- those old
-- freeform columns stay exactly as they are, unused going forward, so
-- nothing is lost if this ever needs to be reverted. Instead, any Program
-- with text already in one of those fields gets ONE new contact row per
-- field, category set accordingly, with the entire old block dropped into
-- that row's new Notes field -- nothing parsed or split up automatically
-- (that can't be done reliably from freeform text), just carried over
-- intact so whoever cleans it up can see exactly what was there before and
-- re-key it into the proper Name/Title/Address/Email/Phone fields at their
-- own pace.
--
-- Safe to re-run -- the backfill only inserts for a Program/category that
-- doesn't already have at least one contact row, so running this twice
-- won't create duplicates.

do $$ begin
  create type partner_contact_category_type as enum ('cc_list', 'contract_signer', 'program_administrator', 'program_finance');
exception
  when duplicate_object then null;
end $$;

alter table econ_dev_partner_contacts add column if not exists category partner_contact_category_type not null default 'cc_list';
alter table econ_dev_partner_contacts add column if not exists address text;
alter table econ_dev_partner_contacts add column if not exists notes text;

insert into econ_dev_partner_contacts (organization_id, partner_id, category, name, notes, sort_order)
select c.organization_id, c.id, 'contract_signer', 'Imported from Contract Signer', c.contract_signer, 0
from econ_dev_companies c
where coalesce(nullif(trim(c.contract_signer), ''), '') <> ''
  and not exists (
    select 1 from econ_dev_partner_contacts x where x.partner_id = c.id and x.category = 'contract_signer'
  );

insert into econ_dev_partner_contacts (organization_id, partner_id, category, name, notes, sort_order)
select c.organization_id, c.id, 'program_administrator', 'Imported from Program Administrator', c.program_administrator, 0
from econ_dev_companies c
where coalesce(nullif(trim(c.program_administrator), ''), '') <> ''
  and not exists (
    select 1 from econ_dev_partner_contacts x where x.partner_id = c.id and x.category = 'program_administrator'
  );

insert into econ_dev_partner_contacts (organization_id, partner_id, category, name, notes, sort_order)
select c.organization_id, c.id, 'program_finance', 'Imported from Program Finance', c.address, 0
from econ_dev_companies c
where coalesce(nullif(trim(c.address), ''), '') <> ''
  and not exists (
    select 1 from econ_dev_partner_contacts x where x.partner_id = c.id and x.category = 'program_finance'
  );
