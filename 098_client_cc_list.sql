-- 098_client_cc_list.sql
--
-- Greg (8/31/26): "i need to be able to add a few people to cc list on an
-- engagement. need a cc list field with one line per cc person with
-- fields, name title email."
--
-- A new, separate list from Company Contacts (client_contacts) -- these
-- are people to keep in the loop on engagement-related emails (updates,
-- the Close-Out Evaluation, etc.) who may not be an actual point of
-- contact at the company itself. Same shape/RLS pattern as
-- client_contacts (019_client_profile_content.sql), just without a phone
-- column since only Name/Title/Email were asked for.
--
-- This migration only adds the table backing the new "CC List" section
-- in client_profile.html (Step 3, right under Company Contacts). It does
-- NOT yet wire this list into any outgoing email's CC line -- the
-- Close-Out Evaluation email (client_workflow_files.html) currently only
-- has a To field, no CC field at all, so that would be a separate,
-- deliberate wiring step later if wanted.
--
-- Safe to re-run.

create table if not exists client_cc_list (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid not null references clients(id) on delete cascade,
  name        text not null,
  title       text,
  email       text,
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now()
);

alter table client_cc_list enable row level security;

drop policy if exists client_cc_list_select on client_cc_list;
create policy client_cc_list_select on client_cc_list for select
using ( is_super_admin() or is_assigned_to_client(client_id) );

drop policy if exists client_cc_list_write on client_cc_list;
create policy client_cc_list_write on client_cc_list for all
using ( is_super_admin() or is_assigned_to_client(client_id) )
with check ( is_super_admin() or is_assigned_to_client(client_id) );
