-- 160: trim the standard Resource Vault to five documents
--
-- Greg (10/9/26), on a screenshot of a client's Resource Vault: "remove the
-- highlighted documents from the standard list of Resources. When you are
-- done there should just be the five that are mentioned in the Welcome
-- Letter."
--
-- OUT (6):
--   EG Marketing Principles
--   EG Frameworks Overview
--   Intercept Marketing
--   EG Deliverables  x3  -- the same YouTube URL entered three times on
--                           9/24 (punch list item 406)
-- LEFT STANDING (5):
--   EG - What to Expect
--   EG FAQs
--   EG 5 Frameworks Videos
--   Keirsey Work Style Preference
--   Signals of Change
--
-- BOTH TABLES, and that is the part worth knowing. A client dashboard does
-- not read resource_vault_templates: it reads client_resource_vault_items,
-- one row per engagement, joined back to the template for its title and
-- link (get_client_public_view). Deleting a template alone would leave
-- every existing engagement still showing the row, with its text gone.
-- So the per-engagement copies go first, then the templates themselves.
--
-- Run this in the Supabase SQL editor. It was written for the MCP tools but
-- every DELETE against these two tables timed out there at 180s twice
-- running, with nothing committed either time -- the same hang this project
-- has hit on deletes before. Reads are unaffected.

begin;

with doomed as (
  select id from resource_vault_templates
  where id in (
    'ee9f62c8-84c5-4659-97c4-76d3b7ebde2f',  -- EG Marketing Principles
    'd4b11580-3260-413f-851f-b6b0cafa3533',  -- EG Frameworks Overview
    '93996f09-1eb1-4653-ad6d-85197c1c959d',  -- Intercept Marketing
    '9e20e6bf-7233-49c1-b1aa-e47e85d9b162',  -- EG Deliverables (Short Video)
    '0ca90e21-ac90-4876-904f-fc2f13c23fb1',  -- EG Deliverables (Short Video)
    'ae9d4bb9-1bfd-45b1-9de3-179cee9ca8b4'   -- EG Deliverables (Short Overview)
  )
)
delete from client_resource_vault_items r
using doomed d
where r.template_id = d.id;          -- expects 34 rows

delete from resource_vault_templates
where id in (
  'ee9f62c8-84c5-4659-97c4-76d3b7ebde2f',
  'd4b11580-3260-413f-851f-b6b0cafa3533',
  '93996f09-1eb1-4653-ad6d-85197c1c959d',
  '9e20e6bf-7233-49c1-b1aa-e47e85d9b162',
  '0ca90e21-ac90-4876-904f-fc2f13c23fb1',
  'ae9d4bb9-1bfd-45b1-9de3-179cee9ca8b4'
);                                    -- expects 6 rows

-- Signals of Change was 8th of eleven; with six gone it is simply fifth.
update resource_vault_templates
set sort_order = 5
where id = '05b06349-a89d-479e-8301-138fec11fbf4';

commit;

-- Check: should be 5 templates, and no engagement showing more than 5.
-- select count(*) from resource_vault_templates;
-- select client_id, count(*) from client_resource_vault_items group by 1 order by 2 desc;
