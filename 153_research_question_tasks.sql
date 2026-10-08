-- 153: optional per-question tasks, the Podio habit a couple of Team Leads
-- still want.
--
-- Greg (10/8/26): "podio has a section to add tasks (assign Controlling
-- Document questions to specialists). very few tl's use it but a couple find
-- it helpful. when the specialist has completed their research and added
-- their files they tick off the task as completed."
--
-- No new task table. A task IS a research question -- the thing being
-- assigned already exists in client_research_questions, numbered, with its
-- background text, and documents.question_id already files a specialist's
-- files under it. Greg: "adding a file to the task would also add it to the
-- Add Research section so that if the specialist added the file to the task
-- they don't have to also add it to the Research section." That is free,
-- because there is only one place a file can go: the task view and the
-- research view are two renderings of the same rows. A separate tasks table
-- would have had to be kept in step with the questions, and would have been
-- the thing that eventually drifted.
--
-- So this migration is four columns and a flag.
--
-- Hours are deliberately absent. Greg: "the only thing that counts hours is
-- the Team & Hours page. there are no hours associated with tasks."
--
-- assigned_user_id is stored rather than derived from the work area, which
-- was the first instinct. The data says it cannot be derived: market_research
-- and gis both run to two slots on a third of live engagements, so "the work
-- area's specialist" has two answers there -- and splitting questions between
-- two people on one area is exactly what the Podio list being copied does.
-- The interface defaults it from the work area and only offers specialists
-- already assigned to the engagement, so it still "lines up with the Work
-- Area and Specialist" without pretending there is only ever one of them.

alter table clients
  add column if not exists use_tasks boolean not null default false;

comment on column clients.use_tasks is
  'Team Lead opt-in for the per-question task list. Off by default: most Team Leads do not work this way and should not see the controls.';

alter table client_research_questions
  add column if not exists assigned_user_id uuid references users(id) on delete set null,
  add column if not exists due_date         date,
  add column if not exists completed_at     timestamptz,
  add column if not exists completed_by     uuid references users(id) on delete set null;

comment on column client_research_questions.assigned_user_id is
  'Specialist responsible for this question when the engagement uses tasks. Defaults in the UI from the question''s work area.';
comment on column client_research_questions.completed_at is
  'Set when the assignee ticks the task off; null means outstanding.';

-- Finding assignments for one engagement's task list, and a specialist
-- finding their own outstanding work across engagements.
create index if not exists client_research_questions_assigned_idx
  on client_research_questions (assigned_user_id)
  where assigned_user_id is not null;

-- No policy changes. client_research_questions already carries
--   select/all using (is_super_admin() OR is_assigned_to_client(client_id))
-- so the assigned specialist can already tick their own task off, and nobody
-- off the engagement can see it. clients.use_tasks inherits the same
-- Team-Lead-or-Admin write rule that show_research_questions runs under.
