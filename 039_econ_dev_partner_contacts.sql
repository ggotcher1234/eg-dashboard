-- 039_econ_dev_partner_contacts.sql
--
-- Depends on 038_team_contact_details.sql.
--
-- Greg: "I need a way to add non-consultants to the EG Team. Some of them
-- will be representatives of the Economic Development Partner for that
-- account... typically, the way I get this information is in an updated
-- spreadsheet a couple of times per year." His own proposal, confirmed:
-- update the Econ Dev Partners page to include contacts per partner, then
-- make them selectable as members of a client's Economic Gardening Team.
--
-- This migration adds the first half: a contacts list per econ_dev_companies
-- row. Same shape as client_contacts (name/title/email/phone), scoped to a
-- partner instead of a client. RLS mirrors resource_vault_templates: any
-- org member can read (so consultants can browse before selecting), only
-- Super Admin can write (Section 5.1 -- this is the same internal directory
-- as the partner list itself, which is Super-Admin-managed).
--
-- organization_id is denormalized onto this table (copied from the parent
-- partner at insert time) rather than joined through econ_dev_companies on
-- every RLS check -- same tradeoff resource_vault_templates makes.
--
-- The second half (client-level selection of which contacts show on which
-- client's public dashboard) is 040_client_team_partner_contacts.sql.
--
-- Safe to re-run.

create table if not exists econ_dev_partner_contacts (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  partner_id      uuid not null references econ_dev_companies(id) on delete cascade,
  name            text not null,
  title           text,
  email           text,
  phone           text,
  active          boolean not null default true,
  sort_order      integer not null default 0,
  created_at      timestamptz not null default now()
);

create index if not exists econ_dev_partner_contacts_partner_id_idx on econ_dev_partner_contacts(partner_id);

alter table econ_dev_partner_contacts enable row level security;

drop policy if exists econ_dev_partner_contacts_select on econ_dev_partner_contacts;
create policy econ_dev_partner_contacts_select on econ_dev_partner_contacts for select
using ( is_org_member(organization_id) or is_super_admin() );

drop policy if exists econ_dev_partner_contacts_write on econ_dev_partner_contacts;
create policy econ_dev_partner_contacts_write on econ_dev_partner_contacts for all
using ( is_super_admin() )
with check ( is_super_admin() );
