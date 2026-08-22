-- 066_public_program_applications.sql
--
-- Greg (8/21/26): "each Program has their own tailored application url that
-- they give to worthy CEOs to fill out and submit for an EG Engagement...
-- when submitted, it adds the application as a DRAFT to our system."
--
-- This is a PUBLIC, no-login page (client_application_public.html) --
-- there's no signed-in user, so it can't write directly to
-- client_application_drafts under the existing RLS (every policy on that
-- table keys off auth.uid()). Rather than open a new anon-insert policy on
-- a table that also holds real staff drafts, the public page posts to a
-- new Edge Function (public-submit-application) that uses the service-role
-- key -- the ONE place these public submissions ever touch the database,
-- same pattern as admin-create-team-member. No new RLS surface for anon at
-- all; this migration only needs to (a) let a draft exist with no creator,
-- and (b) let Team Leads/Super Admins (not just the row's own creator) see
-- and act on the ones that come in this way, since Chris/Rita review these
-- and may not be Super Admins.
--
-- Safe to re-run.

-- ---------- 1. Let a draft exist with no internal creator ----------
-- created_by was `not null references users(id)` -- fine for the internal
-- wizard's autosave (always a signed-in staff member), but a public
-- submission has no EG Dashboard login behind it at all.
alter table client_application_drafts alter column created_by drop not null;

-- Which Program this came in through, and how it was created -- lets the
-- Drafts list (client_applications.html) show/filter externally-submitted
-- applications separately from a staff member's own in-progress typing.
alter table client_application_drafts add column if not exists econ_dev_company_id uuid references econ_dev_companies(id) on delete set null;
alter table client_application_drafts add column if not exists source text not null default 'internal';
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'client_application_drafts_source_check'
  ) then
    alter table client_application_drafts
      add constraint client_application_drafts_source_check
      check (source in ('internal', 'public_application'));
  end if;
end $$;

-- ---------- 2. Broaden who can see/manage a public submission ----------
-- created_by is null on these, so the existing "created_by = auth.uid()"
-- clause never matches them -- previously that meant only a literal Super
-- Admin could see one. Team Leads review applications too (Podio parity,
-- see 050), so they need the same visibility for anything that came in
-- through a Program's public link.
drop policy if exists client_application_drafts_select on client_application_drafts;
create policy client_application_drafts_select on client_application_drafts for select
using (
  created_by = auth.uid()
  or is_super_admin()
  or (
    source = 'public_application'
    and exists (select 1 from users u where u.id = auth.uid() and u.role in ('team_lead', 'super_admin'))
  )
);

drop policy if exists client_application_drafts_update on client_application_drafts;
create policy client_application_drafts_update on client_application_drafts for update
using (
  created_by = auth.uid()
  or is_super_admin()
  or (
    source = 'public_application'
    and exists (select 1 from users u where u.id = auth.uid() and u.role in ('team_lead', 'super_admin'))
  )
)
with check (
  created_by = auth.uid()
  or is_super_admin()
  or (
    source = 'public_application'
    and exists (select 1 from users u where u.id = auth.uid() and u.role in ('team_lead', 'super_admin'))
  )
);

drop policy if exists client_application_drafts_delete on client_application_drafts;
create policy client_application_drafts_delete on client_application_drafts for delete
using (
  created_by = auth.uid()
  or is_super_admin()
  or (
    source = 'public_application'
    and exists (select 1 from users u where u.id = auth.uid() and u.role in ('team_lead', 'super_admin'))
  )
);

-- Note: no new INSERT policy is added -- public submissions never use the
-- anon key against this table at all; they go through the Edge Function's
-- service-role client, which bypasses RLS entirely (same as every other
-- write-from-an-Edge-Function in this app).

-- ---------- 3. Program logo, for the branded public application page ----------
alter table econ_dev_companies add column if not exists logo_url text;

-- The public application page needs to look up a Program by its ?program=
-- code with no login at all. Rather than open a blanket anon SELECT policy
-- on econ_dev_companies (which also holds each program's mailing address),
-- this is a narrow security-definer RPC that only ever hands back the four
-- fields the branded page actually shows -- same shape as
-- get_client_public_view()'s anon-facing design elsewhere in this app.
create or replace function get_public_program_by_code(p_code text)
returns table (id uuid, name text, code text, logo_url text)
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select id, name, code, logo_url
  from econ_dev_companies
  where lower(code) = lower(p_code) and active = true
  limit 1;
$$;

grant execute on function get_public_program_by_code(text) to anon, authenticated;

insert into storage.buckets (id, name, public)
values ('program-logos', 'program-logos', true)
on conflict (id) do update set public = true;

-- Write: Super Admin only, uploaded from the Programs admin screen.
-- Path convention: programs/{program_id}/logo/{filename}.
drop policy if exists "program logos write" on storage.objects;
create policy "program logos write" on storage.objects for all
using (
  bucket_id = 'program-logos'
  and (storage.foldername(name))[1] = 'programs'
  and is_super_admin()
)
with check (
  bucket_id = 'program-logos'
  and (storage.foldername(name))[1] = 'programs'
  and is_super_admin()
);

-- Read: the bucket's public flag already lets anyone (including an
-- anonymous CEO on the public application page) fetch a logo via its
-- public URL without touching RLS -- this just covers the authenticated
-- SDK path so the upload UI works the same for staff.
drop policy if exists "program logos read" on storage.objects;
create policy "program logos read" on storage.objects for select
using (bucket_id = 'program-logos');

-- ---------- 4. Attachments a CEO uploads with their application ----------
-- Written ONLY by the public-submit-application Edge Function's
-- service-role client (bypasses storage RLS, same as the table above) --
-- no anon policy needed at all. Public bucket so staff can click a link
-- straight out of a draft's data to view what was attached.
insert into storage.buckets (id, name, public)
values ('program-application-attachments', 'program-application-attachments', true)
on conflict (id) do update set public = true;

drop policy if exists "program application attachments read" on storage.objects;
create policy "program application attachments read" on storage.objects for select
using (bucket_id = 'program-application-attachments');
