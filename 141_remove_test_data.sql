-- 141_remove_test_data.sql   (10/5/26)
--
-- GO-LIVE CLEANUP. Not part of the schema -- this is the undo for the
-- temporary test data tool on client_applications.html (the panel on the
-- "No application selected" screen, marked TEMPORARY in both the markup
-- and the script).
--
-- Run this when the system goes live, then delete the two marked blocks
-- from client_applications.html -- or set TEST_TOOLS = false to leave the
-- code in place and switch the panel off.
--
-- HOW TEST ROWS ARE FOUND. Every application the tool writes is tagged
-- 'TEST DATA' in client_applications.tags and named with a 'TEST -- '
-- prefix. The engagement an accepted one becomes takes the application's
-- company_name, so it carries the same prefix -- but clients has no tags
-- column, so engagements are found two ways: by the application still
-- pointing at them (exact, and the reason the engagements are deleted
-- before the applications that name them) and by the name prefix, which
-- catches one whose application somebody already removed by hand.
--
-- WHAT GOES WITH THEM. Every child table of clients is ON DELETE CASCADE
-- -- assignments, contacts, content, documents, research questions, next
-- steps, share links, evaluation responses, delay notes, snapshots,
-- notifications, audit rows -- so deleting the engagement takes all of it.
-- client_applications.client_id is the one exception, ON DELETE SET NULL,
-- which is why the applications are deleted in their own statement after.
--
-- NOT REMOVED: files already uploaded to Supabase Storage. Deleting a
-- documents row does not delete the object behind it. They are harmless
-- once nothing links to them, but to clear them too, list them from the
-- Storage browser BEFORE running this -- their paths start with the
-- client id of an engagement this deletes, and afterwards there is
-- nothing left to look the ids up from.
--
-- SAFETY. Run section 1 on its own first and read the list. This cannot
-- be undone, and one of the two matches is a name prefix, so a real
-- engagement genuinely called "TEST -- something" would go with the rest.

-- ---------- 1. look before you leap ----------
-- The engagements that will go:
select c.id, c.name, c.project_status, c.created_at,
       (a.id is not null) as matched_by_application
from clients c
left join client_applications a
  on a.client_id = c.id
 and ('TEST DATA' = any(coalesce(a.tags, '{}')) or a.company_name like 'TEST -- %')
where a.id is not null
   or c.name like 'TEST -- %'
order by c.created_at;

-- The applications that will go:
select a.id, a.company_name, a.status, a.client_id, a.submitted_at
from client_applications a
where 'TEST DATA' = any(coalesce(a.tags, '{}'))
   or a.company_name like 'TEST -- %'
order by a.submitted_at;

-- ---------- 2. the deletes ----------
-- Engagements first -- this cascades through every child table, and has
-- to happen while the applications still point at them.
delete from clients c
where exists (
        select 1 from client_applications a
        where a.client_id = c.id
          and ('TEST DATA' = any(coalesce(a.tags, '{}')) or a.company_name like 'TEST -- %')
      )
   or c.name like 'TEST -- %';

-- Then the applications, including any that were never accepted.
delete from client_applications a
where 'TEST DATA' = any(coalesce(a.tags, '{}'))
   or a.company_name like 'TEST -- %';

-- ---------- 3. confirm ----------
select
  (select count(*) from clients where name like 'TEST -- %') as engagements_left,
  (select count(*) from client_applications
     where 'TEST DATA' = any(coalesce(tags, '{}')) or company_name like 'TEST -- %') as applications_left;
