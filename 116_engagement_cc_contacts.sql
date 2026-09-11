-- 116_engagement_cc_contacts.sql
--
-- Depends on 039_econ_dev_partner_contacts.sql (the Program's contacts) and
-- 112_program_contacts_and_address.sql (the role flags on them). Mirrors
-- 040_client_team_partner_contacts.sql exactly -- same shape, same RLS.
--
-- Chris/Rita review (9/11/26): "The CC list will be managed per-engagement
-- during application approval, not at the program level, to ensure team leads
-- only communicate with relevant partners." Greg (9/11/26): "this goes on the
-- submitted application form in the area where we add the Team Lead and
-- hours. list the program administrators with check boxes for the CC list."
--
-- WHY A SEPARATE TABLE FROM client_team_partner_contacts
-- That table already joins a client to a Program contact, and the temptation
-- is to reuse it. It means something else: who appears on the CLIENT'S OWN
-- dashboard as part of their Economic Gardening team. Ticking someone for CC
-- would then also publish them to the client's page, which is not the same
-- decision and not the same audience. Two tables, two questions.
--
-- WHY NOT include_on_cc ON THE CONTACT
-- That flag is what this replaces. It says "copy this person on everything
-- this Program touches" -- which is exactly the behaviour Rita objected to:
-- a Team Lead emailing a Program about an engagement that Program has no
-- part in. 112 added it; this supersedes it. The flag stays on the table for
-- now so nothing breaks mid-migration, and the Program form's CC tickbox
-- comes off in a separate change once this is in use.
--
-- Safe to re-run.

create table if not exists client_cc_contacts (
  id                 uuid primary key default gen_random_uuid(),
  client_id          uuid not null references clients(id) on delete cascade,
  partner_contact_id uuid not null references econ_dev_partner_contacts(id) on delete cascade,
  created_at         timestamptz not null default now(),
  unique (client_id, partner_contact_id)
);

comment on table client_cc_contacts is
  'Who gets copied on correspondence for ONE engagement. Chosen at approval
   from the Program''s own contacts. Not the same as client_team_partner_contacts,
   which is who the client sees on their dashboard.';

create index if not exists client_cc_contacts_client_id_idx
  on client_cc_contacts(client_id);

alter table client_cc_contacts enable row level security;

-- Same audience as the engagement's team list: a Super Admin, or anyone
-- assigned to the engagement. A Team Lead needs to read it to know who
-- they're copying, and to correct it without waiting on Rita.
drop policy if exists client_cc_contacts_select on client_cc_contacts;
create policy client_cc_contacts_select on client_cc_contacts for select
using ( is_super_admin() or is_assigned_to_client(client_id) );

drop policy if exists client_cc_contacts_write on client_cc_contacts;
create policy client_cc_contacts_write on client_cc_contacts for all
using ( is_super_admin() or is_assigned_to_client(client_id) )
with check ( is_super_admin() or is_assigned_to_client(client_id) );
