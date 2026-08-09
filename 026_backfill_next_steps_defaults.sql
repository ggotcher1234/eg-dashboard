-- 026_backfill_next_steps_defaults.sql
--
-- Depends on 025_next_steps_notes_and_defaults.sql.
--
-- 025 only seeds the 6 standard Project Next Steps for clients accepted
-- AFTER it's applied (it's wired into accept_client_application()).
-- Existing clients -- like Test -- were accepted before that existed, so
-- their Next Steps list is still empty.
--
-- This is a one-time backfill: for every client that currently has ZERO
-- rows in client_next_steps, insert the same 6 standard steps. Clients
-- that already have their own next steps (added by hand) are left alone
-- entirely -- this only fills in the gap, it never touches or duplicates
-- existing rows.
--
-- Safe to re-run -- once a client has at least one next_steps row (either
-- from this script or from accept_client_application), it's skipped on
-- future runs.

insert into client_next_steps (client_id, description, notes, completed, sort_order)
select c.id, steps.description, steps.notes, false, steps.sort_order
from clients c
cross join (
  values
    ('Send EG Invitation Email', null::text, 1),
    ('Discovery Call', null::text, 2),
    ('Controlling Document', 'Agree on documented research approach', 3),
    ('Research Controlling Document', 'Assign EG team to research areas', 4),
    ('Client Research Review Call', 'Zoom Call with Researchers', 5),
    ('Close-Out Survey', 'How did we do?', 6)
) as steps(description, notes, sort_order)
where not exists (
  select 1 from client_next_steps existing where existing.client_id = c.id
);
