-- 156: the per-question due date comes back, seeded from the engagement.
--
-- Greg (10/8/26): "let's keep the due date for each question so that if
-- needed, it could be edited on a line by line basis but the master date set
-- by the team lead would be it's initial input but it could be edited by the
-- Team Lead. Then we can add back in your indicator pills for how many days
-- left and overdue."
--
-- 155 had just finished deprecating this column in favour of one date per
-- engagement. The answer turns out to be both: one date the Team Lead sets,
-- which every task starts from, and a date per task for the exception.
--
-- Comments only -- the column itself never went anywhere, which is the
-- payoff for not dropping it (a DROP hangs for 180s through the MCP
-- connection these are applied over, see 145, and that caution is why
-- un-deprecating costs nothing here).
--
-- Applied 10/8/26.

comment on column client_research_questions.due_date is
  'Due date for this one task. Seeded from clients.research_due_date when the task is created or when the Team Lead moves the engagement date, and editable line by line from there (Greg, 10/8/26: the master date "would be it''s initial input but it could be edited by the Team Lead"). A value that differs from the engagement date was set deliberately and is left alone when the engagement date moves.';

comment on column clients.research_due_date is
  'Target date for ALL research on this engagement, set by the Team Lead. Not the whole story: it is the default each task starts from, and a task can be moved off it. Changing it rolls down to every incomplete task still sitting on the old date (or on no date) and leaves individually-dated tasks where they are.';
