-- 160: trim the standard Resource Vault, Deliverables video on top
--
-- Greg (10/9/26), on a screenshot of a client's Resource Vault: "remove the
-- highlighted documents from the standard list of Resources. When you are
-- done there should just be the five that are mentioned in the Welcome
-- Letter." Then: "add one row back at the top for the Deliverables video."
--
-- MOST OF THIS IS ALREADY DONE. Everything that is not a deletion ran
-- through the MCP tools on 10/9:
--   * EG Deliverables (9e20e6bf, the oldest of the three identical rows)
--     moved to sort_order 0, top of the list
--   * Signals of Change moved to sort_order 5
--   * the one engagement that held a duplicate but not the survivor got a
--     row for it, and all 7 engagements now carry it at the top
--
-- WHAT IS LEFT is the five deletions below, and they have to be run by
-- hand. Every DELETE through the Supabase MCP tools hangs for 180s and
-- commits nothing, while UPDATE and INSERT go straight through in under a
-- second and pg_stat_activity shows no lock and no stuck transaction --
-- the tool holds destructive statements for a confirmation that never
-- reaches this session. Nothing to do with database permissions.
--
-- TWO WAYS TO FINISH, whichever is easier:
--
--   1. Paste this into the Supabase SQL editor.
--   2. Delete these five rows on the EGDB Resource Templates page.
--      client_resource_vault_items.template_id is ON DELETE CASCADE, so
--      removing a template takes every engagement's copy with it. That is
--      also why this file no longer touches the per-engagement table.
--
-- Either way the Vault ends up as:
--   0  EG Deliverables              Short Video
--   1  EG - What to Expect
--   2  EG FAQs
--   3  EG 5 Frameworks Videos
--   4  Keirsey Work Style Preference
--   5  Signals of Change

delete from resource_vault_templates
where id in (
  'ee9f62c8-84c5-4659-97c4-76d3b7ebde2f',  -- EG Marketing Principles
  'd4b11580-3260-413f-851f-b6b0cafa3533',  -- EG Frameworks Overview
  '93996f09-1eb1-4653-ad6d-85197c1c959d',  -- Intercept Marketing
  '0ca90e21-ac90-4876-904f-fc2f13c23fb1',  -- EG Deliverables (duplicate, 9/24 21:18)
  'ae9d4bb9-1bfd-45b1-9de3-179cee9ca8b4'   -- EG Deliverables (duplicate, "Short Overview")
);                                          -- 5 templates, 28 client rows by cascade

-- Check: 6 templates, and every engagement showing the same 6.
-- select title, description, sort_order from resource_vault_templates order by sort_order;
-- select client_id, count(*) from client_resource_vault_items group by 1 order by 2 desc;
