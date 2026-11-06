-- 190: when the Controlling Document draft email was taken.
--
-- Greg (11/6/26): "let's capture the date the email of the CD draft was
-- created with Emailed Draft Email: Date".
--
-- Same shape as 185's scheduling_letter_taken_at, and for the same reason:
-- the Team Lead sends the Controlling Document out for the client to rank,
-- then waits. Until the client submits there is nothing on the row to say
-- whether it ever went out, so a week later the only way to know is to go
-- looking in Sent Mail.
--
-- "Taken", not "sent": the app hands over a draft and the Team Lead sends it
-- from their own mail client, which this page never sees. The stamp is set
-- when the draft is actually taken -- Outlook Email, or Your Email copying it
-- to the clipboard -- not when the composer is opened, since opening one and
-- closing it again is how you check the wording.
--
-- Not a gate on anything, and re-sending simply moves the stamp forward: a
-- second CEO, a resend after a bounce, and a corrected link are all normal.
alter table public.client_content
  add column if not exists controlling_draft_emailed_at timestamptz,
  add column if not exists controlling_draft_emailed_by uuid references auth.users(id);
