-- 158: un-archive the account Greg actually signs in with.
--
-- Greg (10/8/26): "i just invited Julie Dryer to join the dashboard. when I
-- clicked to send the invitation i got a message that her roster had been
-- archived. that's bad. i don't know if she got the invitation and i had to
-- check and see if she had been moved to archive. she had not."
--
-- She had not, and the message was never about her. admin-create-team-member
-- looks the CALLER up by auth id and refuses an archived one with "This
-- account has been archived." -- no subject in the sentence, so it reads as
-- being about the person on screen. It was about Greg.
--
-- On 10/6 18:07:41 two Greg rows were archived in one stroke, tidying up the
-- duplicate accounts from 144. The wrong pair went: it archived
-- greg@leadforcesolutions.com -- the account he signs in with every day,
-- last seen 10/8 19:58 -- and left greg.gotcher@leadforcesolutions.com,
-- which he has not used since 10/6, active.
--
-- The auth-level ban that archiving is supposed to apply never took
-- (banned_until is null on all three rows), which is why he could keep
-- signing in and why this went unnoticed for two days: everything that
-- reads the database worked, and only the three Edge Functions that check
-- archived_at on the caller refused him --
--
--   admin-create-team-member   (add, archive, restore, invite)
--   admin-approve-application  (approving an application at all)
--   regenerate-evaluation-pdf  (the Build PDF button)
--
-- -- plus the admin notification lists, which select
-- `.is("archived_at", null)`, so he stopped receiving new-application email
-- on 10/6 as well.
--
-- Only archived_at and archived_by are cleared. hidden_from_roster stays
-- true on this row deliberately: his Roster card is the
-- greg.gotcher@leadforcesolutions.com row, and un-hiding this one would put
-- a second Greg on the Roster -- the very thing 144 was cleaning up. Which
-- of the two should be the lasting account is still an open question, and
-- not one to answer by accident at 8pm the night before a meeting.
--
-- The gmail row stays archived; it was correctly archived.
--
-- Applied 10/8/26.

update users
   set archived_at = null,
       archived_by = null
 where id = '1236c809-f3a3-4189-a767-7ad5d31e8314'
   and email = 'greg@leadforcesolutions.com';
