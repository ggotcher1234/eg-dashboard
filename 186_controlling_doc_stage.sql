-- 186: is this Controlling Document a draft, or the final one?
--
-- Greg (11/3/26): "add two checkboxes to indicate if this version is a draft
-- or the final controlling document. Change the title of the document to
-- match the box that is checked."
--
-- A Controlling Document goes to the CEO for review, comes back marked up,
-- and goes round again before anyone commits to it. Which pass you are
-- holding was nowhere on the document, which matters most on a printout that
-- has left the building.
--
-- Nullable on purpose, and no default. Neither box ticked is a real state --
-- every document submitted before today is in it -- and reads as the plain
-- "Controlling Document", so nothing already on file is retroactively
-- labelled a draft.
alter table public.client_content
  add column if not exists controlling_doc_stage text
  check (controlling_doc_stage in ('draft', 'final'));
