-- 191: when the Discovery Document and Evaluation Sheet emails were taken.
--
-- Greg (11/6/26): "yes, do the same for Discovery and Evaluation sheets."
-- The sibling of 190, which did the Controlling Document draft.
--
-- Same reasoning on all three rows: each ends in a customer email and then a
-- wait, and until the client answers nothing on the row says it ever went
-- out. Stamped when the draft is taken (Outlook Email, or Your Email copying
-- it), not when the composer opens, and re-sending moves the date forward.
--
-- Only the Controlling Document's line says "Draft" -- its email asks the
-- client to review a draft, which is the thing Greg wanted dated. These two
-- send a finished document, so they read "Emailed: <date>".
alter table public.client_content
  add column if not exists discovery_emailed_at  timestamptz,
  add column if not exists discovery_emailed_by  uuid references auth.users(id),
  add column if not exists evaluation_emailed_at timestamptz,
  add column if not exists evaluation_emailed_by uuid references auth.users(id);
