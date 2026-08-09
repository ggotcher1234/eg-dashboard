-- 030_anon_read_client_documents.sql
--
-- Depends on 005_add_application_documents.sql (client-documents bucket +
-- "client-documents access" policy), 021_public_view_full_bundle.sql
-- (get_client_public_view), and 027_resource_vault_templates.sql
-- (client_resource_vault_items.storage_path).
--
-- BUG FIX: the client's public dashboard (client_public.html) is meant to
-- be viewable by anonymous visitors -- get_client_public_view() already
-- runs with row_security off so it happily hands back document/resource
-- links to anyone with the client's share link. But the actual FILE
-- download always failed for a real anonymous visitor, because the only
-- storage.objects policy on the `clients/{id}/...` path
-- ("client-documents access", from 005) requires
-- `is_super_admin() or is_assigned_to_client(...)` -- both of which need
-- auth.uid(), which anon never has. So every doc-download link on the
-- public dashboard was silently broken for anyone not logged in.
--
-- Fix: add a second, narrowly-scoped SELECT policy just for the `anon`
-- role that allows reading a `clients/{id}/...` object ONLY when it's
-- exactly one of the two kinds of file the public dashboard is already
-- allowed to show:
--   1. a `documents` row with visibility = 'client_facing' (matches the
--      same filter get_client_public_view() uses), or
--   2. a `client_resource_vault_items` row's uploaded file (Resource
--      Vault items don't have a visibility flag -- they're always shown
--      to the client, same as the Resource Vault section itself)
-- ...and only for a client that currently has an active share link.
-- Internal-only documents, and anything for a client whose link has been
-- deactivated, stay unreadable to anon exactly as before.
--
-- This is additive -- the existing "client-documents access" policy for
-- Super Admin / assigned staff is untouched, and this new policy only
-- grants to the `anon` role.
--
-- Safe to re-run.

create or replace function client_public_document_readable(p_storage_path text)
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select exists (
    select 1
    from documents d
    join client_share_links l on l.client_id = d.client_id and l.active
    where d.storage_path = p_storage_path and d.visibility = 'client_facing'
  )
  or exists (
    select 1
    from client_resource_vault_items r
    join client_share_links l on l.client_id = r.client_id and l.active
    where r.storage_path = p_storage_path
  );
$$;

grant execute on function client_public_document_readable(text) to anon, authenticated;

drop policy if exists "clients public document read" on storage.objects;
create policy "clients public document read" on storage.objects for select
to anon
using (
  bucket_id = 'client-documents'
  and (storage.foldername(name))[1] = 'clients'
  and client_public_document_readable(name)
);
