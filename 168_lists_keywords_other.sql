-- 168: Lists gains Keywords and Other.
--
-- Greg (10/12/26): "Let's call this combined section - Lists and go to a
-- single column. add a list/link for Keywords and another for Other with a
-- place to enter what Other is."
--
-- Same file-or-link slot as 167's two, twice more. Other carries its own
-- name as well, because an unnamed "Other" tells the next person nothing --
-- whatever the TL types becomes the slot's heading.

alter table client_content
  add column if not exists keyword_list_url text,
  add column if not exists keyword_list_storage_path text,
  add column if not exists other_list_url text,
  add column if not exists other_list_storage_path text,
  add column if not exists other_list_label text;
