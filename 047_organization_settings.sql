-- 047_organization_settings.sql
--
-- Depends on 027_resource_vault_templates.sql (uses the same
-- is_org_member()/is_super_admin() pattern for RLS).
--
-- Greg: "let's put the $95/hour in an admin field that can be edited"
-- (Invoicing Report follow-up, 8/12/26). The flat specialist pay rate on
-- invoicing_report.html was a hardcoded JS constant; this makes it a real,
-- Admin-editable, per-organization setting instead.
--
-- Using a new dedicated table rather than adding a column to the existing
-- `organizations` table: nothing in this app's code reads or writes
-- `organizations` directly anywhere, so its current RLS policies aren't
-- visible from here. A small settings table lets this ship with its own
-- clean, from-scratch read/write policies (same shape as
-- resource_vault_templates') instead of depending on assumptions about a
-- table this migration can't inspect.
--
-- One row per organization. The backfill insert at the bottom means every
-- existing org already has a row at the default rate the moment this runs
-- -- the app can always just SELECT ... .single() without a "create on
-- first save" branch.
--
-- Safe to re-run.

create table if not exists organization_settings (
  organization_id uuid primary key references organizations(id) on delete cascade,
  hourly_rate     numeric not null default 95,
  updated_at      timestamptz not null default now()
);

alter table organization_settings enable row level security;

drop policy if exists organization_settings_select on organization_settings;
create policy organization_settings_select on organization_settings for select
using ( is_org_member(organization_id) or is_super_admin() );

drop policy if exists organization_settings_write on organization_settings;
create policy organization_settings_write on organization_settings for all
using ( is_super_admin() )
with check ( is_super_admin() );

insert into organization_settings (organization_id)
select o.id from organizations o
where not exists (
  select 1 from organization_settings s where s.organization_id = o.id
);
