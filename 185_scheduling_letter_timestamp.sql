-- 185: record when the Scheduling Letter was taken.
--
-- Greg (11/3/26): "can we time stamp the scheduling letter."
--
-- The letter leaves from the Team Lead's own mail client -- both buttons put
-- it on the clipboard and one of them opens an addressed draft -- so the app
-- never sees it sent and cannot honestly stamp it "sent". What it does see is
-- the moment somebody took it, which is the useful fact anyway: it answers
-- "has this engagement been contacted yet, and how long ago".
--
-- Named for what it records. Stamped by either button, overwritten on each
-- take rather than kept as a history: taking the letter twice is normal (a
-- resend, a second CEO), and the line on screen reads "Last taken ...".
alter table public.client_content
  add column if not exists scheduling_letter_taken_at timestamptz,
  add column if not exists scheduling_letter_taken_by uuid references public.users(id);
