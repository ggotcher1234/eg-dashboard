-- 160: trim the standard Resource Vault to five, Deliverables video on top
--
-- Greg (10/9/26), on a screenshot of a client's Resource Vault: "remove the
-- highlighted documents from the standard list of Resources. When you are
-- done there should just be the five that are mentioned in the Welcome
-- Letter." Then, once the Deliverables duplicates were going to take the
-- video with them: "add one row back at the top for the Deliverables video."
--
-- So one of the three identical EG Deliverables rows survives and moves to
-- the top of the list, and the other two go. FINAL ORDER:
--
--   0  EG Deliverables              Short Video
--   1  EG - What to Expect
--   2  EG FAQs
--   3  EG 5 Frameworks Videos
--   4  Keirsey Work Style Preference
--   5  Signals of Change
--
-- OUT: EG Marketing Principles, EG Frameworks Overview, Intercept Marketing,
-- and two of the three EG Deliverables rows -- the same YouTube URL entered
-- three times on 9/24 (punch list item 406).
--
-- BOTH TABLES, and that is the part worth knowing. A client dashboard does
-- not read resource_vault_templates: it reads client_resource_vault_items,
-- one row per engagement, joined back to the template for its title and
-- link (get_client_public_view). Deleting a template alone would leave every
-- existing engagement showing the row with its text gone. And because the
-- three duplicates were spread unevenly across engagements, one engagement
-- holds a copy of a duplicate but not of the survivor -- step 3 gives it one
-- rather than leaving that client the only one without the video.
--
-- Run this in the Supabase SQL editor. Every DELETE against these two tables
-- timed out at 180s through the MCP tools, twice, committing nothing either
-- time -- the hang this project has hit on deletes before. Reads were fine.

begin;

-- 1. the three documents, and the two duplicate Deliverables rows
with doomed as (
  select id from resource_vault_templates
  where id in (
    'ee9f62c8-84c5-4659-97c4-76d3b7ebde2f',  -- EG Marketing Principles
    'd4b11580-3260-413f-851f-b6b0cafa3533',  -- EG Frameworks Overview
    '93996f09-1eb1-4653-ad6d-85197c1c959d',  -- Intercept Marketing
    '0ca90e21-ac90-4876-904f-fc2f13c23fb1',  -- EG Deliverables (duplicate)
    'ae9d4bb9-1bfd-45b1-9de3-179cee9ca8b4'   -- EG Deliverables (duplicate)
  )
)
delete from client_resource_vault_items r
using doomed d
where r.template_id = d.id;          -- expects 28 rows

delete from resource_vault_templates
where id in (
  'ee9f62c8-84c5-4659-97c4-76d3b7ebde2f',
  'd4b11580-3260-413f-851f-b6b0cafa3533',
  '93996f09-1eb1-4653-ad6d-85197c1c959d',
  '0ca90e21-ac90-4876-904f-fc2f13c23fb1',
  'ae9d4bb9-1bfd-45b1-9de3-179cee9ca8b4'
);                                    -- expects 5 rows

-- 2. the survivor goes to the top; Signals of Change was 8th of eleven and
--    is now simply last of six.
update resource_vault_templates set sort_order = 0
where id = '9e20e6bf-7233-49c1-b1aa-e47e85d9b162';   -- EG Deliverables
update resource_vault_templates set sort_order = 5
where id = '05b06349-a89d-479e-8301-138fec11fbf4';   -- Signals of Change

-- 3. any engagement left without a Deliverables copy gets the survivor.
--    Title, link and description stay null on purpose: the client view
--    coalesces them from the template, so changing the video later is one
--    edit on the Resource Templates page and not seven.
insert into client_resource_vault_items (client_id, template_id, sort_order)
select distinct r.client_id, '9e20e6bf-7233-49c1-b1aa-e47e85d9b162'::uuid, 0
from client_resource_vault_items r
where not exists (
  select 1 from client_resource_vault_items x
  where x.client_id = r.client_id
    and x.template_id = '9e20e6bf-7233-49c1-b1aa-e47e85d9b162'
);

-- 4. and on every engagement, the video sits at the top of the list
update client_resource_vault_items set sort_order = 0
where template_id = '9e20e6bf-7233-49c1-b1aa-e47e85d9b162';

commit;

-- Check: 6 templates, and every engagement showing the same 6.
-- select title, description, sort_order from resource_vault_templates order by sort_order;
-- select client_id, count(*) from client_resource_vault_items group by 1 order by 2 desc;
