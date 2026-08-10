-- 040_client_team_partner_contacts.sql
--
-- Depends on 039_econ_dev_partner_contacts.sql.
--
-- Second half of the partner-contacts feature: which of a client's partner
-- org's contacts (from econ_dev_partner_contacts) should actually appear on
-- THAT client's public Economic Gardening Team list. A partner org (e.g.
-- Virginia Economic Development Partnership) may have a dozen regional
-- contacts on file, but only one or two are relevant to a given client --
-- this is the per-client "select which ones show" step Greg asked for.
--
-- Same RLS shape as client_contacts (Section 4.3 shared-view pattern):
-- readable/writable by Super Admin or anyone assigned to the client.
--
-- unique(client_id, partner_contact_id) so re-checking an already-selected
-- contact is a harmless no-op rather than a duplicate row.
--
-- Safe to re-run.

create table if not exists client_team_partner_contacts (
  id                 uuid primary key default gen_random_uuid(),
  client_id          uuid not null references clients(id) on delete cascade,
  partner_contact_id uuid not null references econ_dev_partner_contacts(id) on delete cascade,
  sort_order         integer not null default 0,
  created_at         timestamptz not null default now(),
  unique (client_id, partner_contact_id)
);

create index if not exists client_team_partner_contacts_client_id_idx on client_team_partner_contacts(client_id);

alter table client_team_partner_contacts enable row level security;

drop policy if exists client_team_partner_contacts_select on client_team_partner_contacts;
create policy client_team_partner_contacts_select on client_team_partner_contacts for select
using ( is_super_admin() or is_assigned_to_client(client_id) );

drop policy if exists client_team_partner_contacts_write on client_team_partner_contacts;
create policy client_team_partner_contacts_write on client_team_partner_contacts for all
using ( is_super_admin() or is_assigned_to_client(client_id) )
with check ( is_super_admin() or is_assigned_to_client(client_id) );
