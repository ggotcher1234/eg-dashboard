-- 155: one research due date for the engagement, not one per task.
--
-- Greg (10/8/26): "The Team Lead sets a target date for completion of all
-- research for all specialists. we almost never set different dates for
-- different research. We try to get all the research done in two weeks but
-- is not always practical so the Team Lead sets a target date for completion
-- and it should role down to all the researchers. no need to show it on
-- every line for each researcher. also, we don't care if a researcher is
-- overdue, we can see if they have uploaded their files or not."
--
-- So the date moves up a level. 153 put due_date on each question because
-- that is where Podio puts it; in practice there is one date per engagement
-- and the per-row copy was six places to change it and six chances for them
-- to disagree.
--
-- Nothing to migrate: of the 16 questions on the four live engagements, zero
-- had a due_date set, so no date is being thrown away or collapsed.
--
-- No policy work either. clients_update already reads
--   using/check (is_super_admin() OR is_team_lead_of_client(id))
-- which is exactly "the Team Lead sets it": the same rule
-- show_research_questions has run under since 123, and the reason a
-- specialist's write is refused rather than needing to be hidden.

alter table clients
  add column if not exists research_due_date date;

comment on column clients.research_due_date is
  'Target date for ALL research on this engagement, set by the Team Lead and shown once at the top of the task list. Usually about two weeks out. Advisory only: nothing warns, badges or escalates off it -- "we don''t care if a researcher is overdue, we can see if they have uploaded their files or not" (Greg, 10/8/26).';

-- The per-question column from 153 is now read by nothing. Left in place
-- rather than dropped: a DROP hangs for 180s through the MCP connection
-- these are applied over (see 145), and an empty column costs nothing. If a
-- genuine per-task exception ever turns up ("almost never" is not never),
-- this is where it goes back.
comment on column client_research_questions.due_date is
  'DEPRECATED by 155: superseded by clients.research_due_date, which covers the whole engagement. Nothing reads or writes this. All values are null.';
