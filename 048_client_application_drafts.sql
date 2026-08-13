-- 048_client_application_drafts.sql
--
-- Greg: "if we save this as a draft, how do we get back to the draft
-- later." Today Save Draft only writes to that one browser's
-- localStorage under a single fixed key -- it can't be resumed from a
-- different device/browser, there's no drafts list, and starting a
-- second application before finishing the first silently overwrites the
-- first draft. This migration adds real server-side storage so drafts
-- persist per person, multiple can exist at once, and they're
-- listable/resumable/deletable from any device.
--
-- One row per in-progress application draft. `data` holds the same flat
-- field-id -> value object the wizard already serializes today
-- (wizSerialize()/wizRestore() in client_applications.html) -- no need to
-- model every wizard field as its own column here. `engagement_name` is
-- denormalized from data['f-company-name'] at save time purely so a
-- drafts list can show/sort by name without unpacking JSONB.
--
-- Access: whoever created a draft can read/update/delete it; Super Admin
-- can also see and clean up any draft in the org (same oversight pattern
-- used for client_applications row deletion elsewhere in this app). The
-- "+ New Application" button itself isn't role-restricted, so any org
-- member (Specialist, Team Lead, Super Admin) can have their own drafts.
--
-- Safe to re-run.

create table if not exists client_application_drafts (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  created_by      uuid not null references users(id) on delete cascade,
  engagement_name text,
  data            jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists client_application_drafts_org_idx
  on client_application_drafts (organization_id, updated_at desc);

alter table client_application_drafts enable row level security;

drop policy if exists client_application_drafts_select on client_application_drafts;
create policy client_application_drafts_select on client_application_drafts for select
using ( created_by = auth.uid() or is_super_admin() );

drop policy if exists client_application_drafts_insert on client_application_drafts;
create policy client_application_drafts_insert on client_application_drafts for insert
with check ( created_by = auth.uid() and is_org_member(organization_id) );

drop policy if exists client_application_drafts_update on client_application_drafts;
create policy client_application_drafts_update on client_application_drafts for update
using ( created_by = auth.uid() or is_super_admin() )
with check ( created_by = auth.uid() or is_super_admin() );

drop policy if exists client_application_drafts_delete on client_application_drafts;
create policy client_application_drafts_delete on client_application_drafts for delete
using ( created_by = auth.uid() or is_super_admin() );
