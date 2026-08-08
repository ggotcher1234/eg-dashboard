-- 019_client_profile_content.sql
--
-- Greg's old standalone dashboard tool (Dropbox/Netlify-based) captures a
-- lot more per client than the new schema does yet: company profile info,
-- social links, EG workflow document links, contacts, competitors, top
-- customers, a resource vault, and a next-steps checklist. This migration
-- adds all of that so the new client-facing dashboard can eventually match
-- it feature-for-feature. Section 4.3's internal/external split still
-- applies: everything added here is CLIENT-FACING content (same zone as
-- client_content/documents), never EG-internal data like hours or pay.
--
-- Safe to re-run.

-- ---- Company profile fields on clients ----
-- These live on `clients` itself (not client_content) because they're
-- basic identity/profile info, same tier as `name`/`slug`, edited on the
-- same screen and by the same people (clients_update: Super Admin or the
-- client's Team Lead) -- no new RLS needed, they ride the existing policy.
alter table clients add column if not exists logo_url        text;
alter table clients add column if not exists website_url     text;
alter table clients add column if not exists address         text;
alter table clients add column if not exists description     text;  -- free text, simple markdown (bold/bullets) rendered client-side
alter table clients add column if not exists naics_codes     text;
alter table clients add column if not exists linkedin_url    text;
alter table clients add column if not exists facebook_url    text;
alter table clients add column if not exists instagram_url   text;
alter table clients add column if not exists twitter_url     text;
alter table clients add column if not exists youtube_url     text;

-- ---- EG Workflow Document links on client_content ----
-- The reference tool's 4-step tracker (Discovery Call Notes / Controlling
-- Document / Research Review / Close-Out Evaluation) is shown ON the
-- client-facing preview, so these belong in the client-facing zone
-- (client_content), not clients.
alter table client_content add column if not exists discovery_doc_url    text;
alter table client_content add column if not exists controlling_doc_url text;
alter table client_content add column if not exists research_review_url text;
alter table client_content add column if not exists closeout_survey_url text;

-- ---- Tag documents with which research area they belong to ----
-- Lets an uploaded file land in one of the four research-area cards on the
-- public page, instead of the old workflow of pasting a Dropbox link.
-- Null means "general" (shows in the plain Documents list, not a specific
-- research card).
do $$ begin
  create type research_area_type as enum ('market_dynamics', 'outbound', 'inbound', 'watering_holes');
exception when duplicate_object then null; end $$;

alter table documents add column if not exists research_area research_area_type;

-- ---- New client-facing content tables ----
-- All follow the same shape/RLS pattern as client_content: readable and
-- writable by Super Admin or anyone assigned to the client (Section 4.3 --
-- "every consultant assigned sees the same full ... record", the same
-- shared-view philosophy already used for hours/assignments).

create table if not exists client_contacts (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid not null references clients(id) on delete cascade,
  name        text not null,
  title       text,
  email       text,
  phone       text,
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now()
);

create table if not exists client_competitors (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid not null references clients(id) on delete cascade,
  name        text not null,
  website_url text,
  notes       text,
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now()
);

create table if not exists client_top_customers (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid not null references clients(id) on delete cascade,
  name        text not null,
  website_url text,
  notes       text,
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now()
);

create table if not exists client_resource_vault_items (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid not null references clients(id) on delete cascade,
  title       text not null,
  url         text not null,
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now()
);

create table if not exists client_next_steps (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid not null references clients(id) on delete cascade,
  description text not null,
  completed   boolean not null default false,
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now()
);

alter table client_contacts             enable row level security;
alter table client_competitors          enable row level security;
alter table client_top_customers        enable row level security;
alter table client_resource_vault_items enable row level security;
alter table client_next_steps           enable row level security;

drop policy if exists client_contacts_select on client_contacts;
create policy client_contacts_select on client_contacts for select
using ( is_super_admin() or is_assigned_to_client(client_id) );
drop policy if exists client_contacts_write on client_contacts;
create policy client_contacts_write on client_contacts for all
using ( is_super_admin() or is_assigned_to_client(client_id) )
with check ( is_super_admin() or is_assigned_to_client(client_id) );

drop policy if exists client_competitors_select on client_competitors;
create policy client_competitors_select on client_competitors for select
using ( is_super_admin() or is_assigned_to_client(client_id) );
drop policy if exists client_competitors_write on client_competitors;
create policy client_competitors_write on client_competitors for all
using ( is_super_admin() or is_assigned_to_client(client_id) )
with check ( is_super_admin() or is_assigned_to_client(client_id) );

drop policy if exists client_top_customers_select on client_top_customers;
create policy client_top_customers_select on client_top_customers for select
using ( is_super_admin() or is_assigned_to_client(client_id) );
drop policy if exists client_top_customers_write on client_top_customers;
create policy client_top_customers_write on client_top_customers for all
using ( is_super_admin() or is_assigned_to_client(client_id) )
with check ( is_super_admin() or is_assigned_to_client(client_id) );

drop policy if exists client_resource_vault_items_select on client_resource_vault_items;
create policy client_resource_vault_items_select on client_resource_vault_items for select
using ( is_super_admin() or is_assigned_to_client(client_id) );
drop policy if exists client_resource_vault_items_write on client_resource_vault_items;
create policy client_resource_vault_items_write on client_resource_vault_items for all
using ( is_super_admin() or is_assigned_to_client(client_id) )
with check ( is_super_admin() or is_assigned_to_client(client_id) );

drop policy if exists client_next_steps_select on client_next_steps;
create policy client_next_steps_select on client_next_steps for select
using ( is_super_admin() or is_assigned_to_client(client_id) );
drop policy if exists client_next_steps_write on client_next_steps;
create policy client_next_steps_write on client_next_steps for all
using ( is_super_admin() or is_assigned_to_client(client_id) )
with check ( is_super_admin() or is_assigned_to_client(client_id) );
