-- 135: remove the duplicate Rita Benson roster entry.
--      (RUN BY GREG IN THE SUPABASE SQL EDITOR, 10/2/26 -- see note below.)
--
-- Rita, for the 10/2 review: "Why am I archived in the roster? My email
-- address needs to be rbenson@economicgardening.org in the roster and I
-- tried to change it and could not."
--
-- She was looking at a second account. The roster carried two Rita Bensons:
--
--   827bebee... rbenson@economicgardening.org  active, super_admin,
--                                              can_approve_applications,
--                                              signed in 9/29      <- hers
--   b3a09072... ritabenson7@gmail.com          archived 9/25, never
--                                              signed in, auth account
--                                              banned by the archive
--
-- The gmail one was the archived row she found, and the email on a roster
-- profile is the sign-in identity, shown as text rather than an editable
-- field -- so there was no way for her to correct it from there, and
-- nothing to correct: her real account already carried the right address.
--
-- The gmail account held nothing: no assignments, time entries, approvals,
-- applications, documents, invoices, next steps, specialties or audit
-- entries -- only two notification_recipients rows, which cascade, and
-- which record that an account that never signed in was notified.
--
-- Deleted rather than left archived: an archived duplicate of a working
-- account is a question waiting to be asked again, by her or by the next
-- person who opens the roster.
--
-- WHY THIS ONE WAS RUN BY HAND: every DELETE sent through the Supabase MCP
-- connection hung for 180s and timed out, including one matching zero rows,
-- while UPDATEs matching zero rows returned instantly -- so it was the
-- statement being blocked somewhere above Postgres, not the data. Reads,
-- inserts, updates and DDL were all unaffected. Greg ran these two
-- statements in the SQL Editor instead.

delete from public.users
 where id = 'b3a09072-298a-4497-987c-bfc36c3ac52d'
   and email = 'ritabenson7@gmail.com';

-- public.users.id does not reference auth.users, so the sign-in record has
-- to go separately or it is left orphaned.
delete from auth.users
 where id = 'b3a09072-298a-4497-987c-bfc36c3ac52d'
   and email = 'ritabenson7@gmail.com';

-- Verified afterwards: one Rita Benson in public.users and one in
-- auth.users, 827bebee..., rbenson@economicgardening.org, not archived.
