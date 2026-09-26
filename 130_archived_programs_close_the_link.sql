-- 130_archived_programs_close_the_link.sql   (9/25/26)
--
-- Greg (9/25/26): "if we archive or delete a program the link goes away too."
-- Half of that was already true. This makes the other half true.
--
-- WHAT WAS ACTUALLY HAPPENING
-- Deleting a Program does remove its link -- the row is gone, so
-- /apply/<code> answers "This application link isn't valid". Correct, and
-- nothing to change.
--
-- Archiving did NOT. The Archive button on the Programs page sets
-- econ_dev_companies.archived = true and nothing else; it never touches
-- `active`, which is the column every public-facing lookup filters on. So an
-- archived Program:
--   * kept its row on the Application Links page, unmarked, with the new Send
--     Link action offered as though nothing had happened, and
--   * kept a live public application form that would happily take a
--     submission for a Program EG had retired.
-- Nothing is archived in the database today, so this has never actually
-- happened. It is being closed before it can.
--
-- WHY NOT JUST SET active = false WHEN ARCHIVING
-- Because `active` and `archived` are not the same question, and collapsing
-- them would be a one-way door. `active` is the older flag and it gates
-- several queries that have nothing to do with the public form; `archived`
-- is a presentation decision Greg makes on the Programs page and undoes with
-- the same button. Teaching the lookup about `archived` leaves both able to
-- mean what they mean, and leaves Unarchive able to put everything back.
--
-- WHY THE FUNCTION NOW RETURNS archived INSTEAD OF FILTERING IT OUT
-- "No such link" and "that Program is closed" are different things to the
-- person holding the link, and only one of them is their mistake. A CEO who
-- was sent a link last week and opens it today should be told the program is
-- no longer accepting applications and who to ask -- not that they typed the
-- URL wrong. Filtering the row out here would make those two cases
-- indistinguishable to the page, so the row comes back with a flag on it and
-- client_application_public.html decides what to say.
--
-- The name and logo of a retired Program are all that is exposed by this, to
-- someone who already had the link. That is the same information the page
-- showed them yesterday.
--
-- DEPLOY ORDER: run this first, then push the HTML, then redeploy
-- public-submit-application (which gets the same guard, so a direct POST
-- cannot go around the closed form).
--
-- Safe to re-run.

-- The return type changes, and Postgres will not replace a function's
-- signature in place, so it is dropped first. Nothing else calls it.
drop function if exists get_public_program_by_code(text);

create function get_public_program_by_code(p_code text)
returns table(id uuid, name text, code text, logo_url text, archived boolean)
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select id, name, code, logo_url, coalesce(archived, false)
  from econ_dev_companies
  where lower(code) = lower(p_code) and active = true
  limit 1;
$$;

comment on function get_public_program_by_code(text) is
  'Looks up a Program for its public application page. Returns the row for an archived Program too, with archived = true, so the page can say "no longer accepting applications" rather than "invalid link" -- the difference matters to a CEO who was given a real link before the Program was retired. An inactive Program returns nothing at all.';

-- Anon holds this through PUBLIC, which is how it was granted before the
-- drop. Restated because DROP took the old grant with it.
grant execute on function get_public_program_by_code(text) to public;

-- ---------- check ----------
-- Expect one row, archived = false, for any live Program.
select * from get_public_program_by_code('ALLOY');

-- And the shape of the data the change acts on.
select
  count(*)                                   as programs,
  count(*) filter (where active)             as active,
  count(*) filter (where archived)           as archived,
  count(*) filter (where active and archived) as active_but_archived
from econ_dev_companies;
