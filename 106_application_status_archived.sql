-- 106_application_status_archived.sql
--
-- Greg (9/2/26): the "Rejected" disposition on the Engagements list
-- (client_applications.html) is now "Archived" -- same slot on the filter
-- bar, friendlier meaning, plus a per-row "Archive" button.
--
-- client_applications.status is the enum `application_status`
-- (values: 'pending', 'accepted', 'rejected'). This adds an 'archived'
-- value and relabels the existing 'rejected' rows. 'rejected' stays in the
-- enum (Postgres can't drop an enum value) -- it's just unused now.
--
-- ============================================================
-- RUN THIS IN TWO SEPARATE STEPS.
-- Postgres will not let you ADD an enum value and USE it in the same
-- transaction, and the Supabase SQL editor runs a whole script as one
-- transaction. So run STEP 1, wait for it to finish, then run STEP 2.
-- ============================================================

-- ---------- STEP 1 (run alone first) ----------
alter type application_status add value if not exists 'archived';


-- ---------- STEP 2 (run after Step 1 succeeds) ----------
-- update client_applications set status = 'archived' where status = 'rejected';
