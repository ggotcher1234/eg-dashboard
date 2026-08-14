-- 050_next_step_assignee.sql
--
-- Greg: the "Tasks Due" tile on the home dashboard was counting every
-- incomplete Project Next Step across a specialist's engagements, which
-- isn't the same thing as "tasks assigned to me" -- Project Next Steps is a
-- shared checklist for the whole engagement team, with no concept of who
-- owns which step. Greg confirmed he wants the real thing: per-step
-- assignment, so the tile (and the editor) can show tasks actually
-- assigned to a specific person.
--
-- Adds a nullable assigned_to column to client_next_steps, referencing
-- users(id). Nullable and ON DELETE SET NULL on purpose -- an unassigned
-- step is a normal, common state (most existing steps have no assignee
-- today), and if the assigned person is later removed from the team, the
-- step shouldn't be deleted, just fall back to unassigned rather than
-- erroring.
--
-- No backfill: there's no reliable way to infer who a step was "for" from
-- existing data (the seeded template steps aren't tied to any one
-- specialty), so every existing step starts unassigned and gets assigned
-- going forward from the editor.
--
-- Safe to re-run.

alter table client_next_steps
  add column if not exists assigned_to uuid references users(id) on delete set null;

create index if not exists client_next_steps_assigned_to_idx on client_next_steps(assigned_to);

-- RLS is unchanged -- client_next_steps_select/_write (from
-- 025_next_steps_notes_and_defaults.sql, itself unchanged since
-- 019_client_profile_content.sql) already scope read/write to
-- is_super_admin() or is_assigned_to_client(client_id), which covers
-- reading/setting assigned_to same as any other column on this table.
