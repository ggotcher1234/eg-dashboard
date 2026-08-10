-- 037_client_logo_upload.sql
--
-- Greg: "change the logo url to logo upload." The Logo URL field on
-- Company Information was a plain pasted URL -- easy to get wrong (people
-- were pasting Dropbox share links, which don't resolve to a raw image and
-- silently fail to display). This adds a real upload control instead.
--
-- Company logos aren't sensitive the way client documents/resources are --
-- they're brand assets the client already displays publicly elsewhere --
-- so rather than routing them through the private client-documents bucket
-- and its signed-URL machinery, this creates a dedicated PUBLIC bucket
-- just for logos. That keeps client-documents' access model (signed URLs,
-- anon gated to specific known-safe rows) completely untouched, and means
-- no changes are needed to get_client_public_view()/finalize_client() or
-- the clients.logo_url column -- it just gets populated with the bucket's
-- public URL after upload instead of a hand-typed one.
--
-- Safe to re-run.

insert into storage.buckets (id, name, public)
values ('client-logos', 'client-logos', true)
on conflict (id) do update set public = true;

-- Write (upload/replace/remove) is gated the same way editing that
-- client's Company Info already is: Super Admin, or anyone assigned to the
-- client. Path convention: clients/{client_id}/logo/{filename}.
drop policy if exists "client logos write" on storage.objects;
create policy "client logos write" on storage.objects for all
using (
  bucket_id = 'client-logos'
  and (storage.foldername(name))[1] = 'clients'
  and (is_super_admin() or is_assigned_to_client(((storage.foldername(name))[2])::uuid))
)
with check (
  bucket_id = 'client-logos'
  and (storage.foldername(name))[1] = 'clients'
  and (is_super_admin() or is_assigned_to_client(((storage.foldername(name))[2])::uuid))
);

-- Read: the bucket's public flag already lets anyone fetch a logo via its
-- public URL without touching RLS at all -- this policy just covers the
-- authenticated SDK path (e.g. listing) so the upload UI itself works the
-- same for every signed-in staff member.
drop policy if exists "client logos read" on storage.objects;
create policy "client logos read" on storage.objects for select
using (bucket_id = 'client-logos');
