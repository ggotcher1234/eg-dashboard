-- 189: a freeform pasted list alongside the file/link on three Lists slots.
--
-- Greg (11/6/26): "for competitors, customers and keywords allow for 1 file
-- upload/link and one freeform text box where we can paste a list that was in
-- an unformatted email to us."
--
-- The file and the link have always been one-or-the-other on a slot -- saving
-- one clears the other -- because they are two ways of pointing at the same
-- document. The pasted list is not a third way of doing that. It is the case
-- where no document exists at all: the client typed the names into the body of
-- an email. So it gets its own column and its own save, and it neither clears
-- nor is cleared by the file/link pair; a slot can legitimately hold an
-- attachment AND the handful of extra names that came in the covering note.
--
-- Stored as the raw text the TL pasted, deliberately unparsed. Whatever shape
-- it arrived in -- one per line, comma-separated, numbered, with a stray
-- signature line -- is the shape that reads back, which is the point: the
-- alternative is guessing at a delimiter and silently losing a row.
--
-- The "Other" slot does not get one. Greg named three.
--
-- client_profile.html asks for these columns in a select of their own and
-- falls back to the file/link columns alone if they are not there yet, so the
-- page is safe to deploy either side of this migration.
alter table public.client_content
  add column if not exists competitor_list_text text,
  add column if not exists customer_list_text  text,
  add column if not exists keyword_list_text   text;
