-- 157: a new question inherits the engagement's research due date.
--
-- Greg (10/8/26): "so all of the task due dates will initially reflect the
-- primary due date set at the top by the TL".
--
-- Nearly true after 156, and the gap was the one that would have been found
-- in use rather than in testing. Three ways a task gets its date:
--
--   1. The Add Research page creates it  -> addTask() seeds it. Covered.
--   2. The Team Lead moves the master    -> rollDownResearchDue() sweeps up
--      every incomplete task still on the old date, and every task with no
--      date at all. Covered.
--   3. A question arrives from the Controlling Document AFTER the master was
--      set -> nothing re-runs the roll-down, so it sat there reading
--      "No date" until somebody touched the engagement date again.
--
-- Case 3 is not an edge case: the Controlling Document is where questions
-- normally come from, and a Team Lead who sets the date early -- which is
-- the point of setting it at the top -- would have hit it every time.
--
-- Fixing it in the page would only have covered the page. A BEFORE INSERT
-- trigger covers every writer there is: the Add Research page under RLS,
-- public-submit-controlling-doc under the service role, and anything added
-- later without remembering this rule.
--
-- It only ever fills a gap, never overwrites: a question created WITH a date
-- keeps it, so the page can still seed its own row optimistically (so the
-- row renders with its pill immediately rather than after a refetch) and a
-- Team Lead can create a task on its own date from the start.
--
-- Verified on applying, in a transaction against Clippard: a question
-- inserted with no date came back carrying the engagement's 2026-10-24, and
-- one inserted with 2026-10-20 kept it.

create or replace function seed_question_due_date()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.due_date is null then
    select c.research_due_date into new.due_date
      from clients c
     where c.id = new.client_id;
  end if;
  return new;
end;
$$;

comment on function seed_question_due_date() is
  'Gives a new research question the engagement''s research_due_date when it has none. SECURITY DEFINER so it reads clients regardless of which surface inserted the row -- the Add Research page under RLS, or public-submit-controlling-doc under the service role.';

drop trigger if exists trg_seed_question_due_date on client_research_questions;
create trigger trg_seed_question_due_date
  before insert on client_research_questions
  for each row execute function seed_question_due_date();
