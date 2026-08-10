-- 042_user_avatar_upload.sql
--
-- Greg: "add upload photo to this popup" (Team Directory profile modal).
-- Same shape as 037_client_logo_upload.sql -- a profile photo isn't
-- sensitive the way client documents are, so it gets its own PUBLIC bucket
-- instead of routing through signed URLs. Populates a new users.avatar_url
-- column with the bucket's public URL after upload, same as logo_url did
-- for clients.
--
-- Write access matches the profile modal's existing edit permission
-- (team_directory.html: `canEdit = isSuperAdmin || u.id === currentUser.id`)
-- -- a consultant can upload their own photo, and a Super Admin can upload
-- anyone's. Path convention: users/{user_id}/avatar/{filename}.
--
-- Safe to re-run.

alter table users add column if not exists avatar_url text;

insert into storage.buckets (id, name, public)
values ('user-avatars', 'user-avatars', true)
on conflict (id) do update set public = true;

drop policy if exists "user avatars write" on storage.objects;
create policy "user avatars write" on storage.objects for all
using (
  bucket_id = 'user-avatars'
  and (storage.foldername(name))[1] = 'users'
  and (is_super_admin() or auth.uid() = ((storage.foldername(name))[2])::uuid)
)
with check (
  bucket_id = 'user-avatars'
  and (storage.foldername(name))[1] = 'users'
  and (is_super_admin() or auth.uid() = ((storage.foldername(name))[2])::uuid)
);

-- Read: the bucket's public flag already lets anyone fetch a photo via its
-- public URL without touching RLS -- this just covers the authenticated
-- SDK path (listing/replacing) so the upload UI works the same for everyone.
drop policy if exists "user avatars read" on storage.objects;
create policy "user avatars read" on storage.objects for select
using (bucket_id = 'user-avatars');
