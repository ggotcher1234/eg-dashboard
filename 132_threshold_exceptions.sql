-- 132_threshold_exceptions.sql   (9/28/26)
--
-- Greg (9/28/26): "we should allow Rita the flexibility to make an exception
-- on criteria if she deems it ok."
--
-- She always could. 131 stores which of the five thresholds have been
-- confirmed; nothing ever stopped her confirming one the application's own
-- answers fail. What was missing is that an exception looked exactly like a
-- clean pass -- tick a company with six employees through "10+ Employees"
-- and the record says Yes, the letter to the Program says Yes, and a year
-- later nobody can tell which engagements were waved through on purpose.
--
-- So this is not a permission. It is the trail behind one.
--
-- WHY A SECOND COLUMN RATHER THAN A RICHER threshold_checks
-- threshold_checks answers one question -- was this confirmed -- and answers
-- it as a plain boolean per key, which is what every reader of it wants.
-- Turning those values into objects to carry a note would mean every place
-- that asks "is this ticked" first has to work out which shape it is looking
-- at, forever, including for the rows 131 already wrote. A note is a
-- different fact about the same key, so it gets its own place, and the
-- absence of a note means what it should: no exception was made.
--
-- Shape: {"employees_10_plus": "Seasonal business -- 14 FTE at peak, Chris
-- agreed on the call"}. Keyed by the same stable ids as threshold_checks.
--
-- WHAT WRITES IT. Only the Accept form, and only when the threshold's own
-- reading of the application says the applicant fails it. A threshold the
-- data cannot settle either way -- "CEO Listed", or a case where the
-- applicant's yes/no and their reported figure disagree -- is not an
-- exception: there the tick IS the judgment, which is what it is there for.
-- A note on a row that passes cleanly would be noise, and is never asked for.
--
-- NOT SHOWN TO THE PROGRAM (Greg, 9/28/26, choosing between the two). The
-- letter to the Program Administrator continues to report all five as
-- passed. The Program is being told the outcome, and NCEG's judgment is what
-- the outcome rests on; the reasoning behind it stays in EGDB, where the
-- people accountable for it can see it.
--
-- Safe to re-run. Depends on 131.

alter table client_applications
  add column if not exists threshold_exceptions jsonb not null default '{}'::jsonb;

comment on column client_applications.threshold_exceptions is
  'Why a review threshold was confirmed despite the application failing it, keyed by the same ids as threshold_checks. Written only when the applicant''s own answers fail that threshold and an Admin confirmed it anyway; cleared when the threshold is unticked. Internal -- deliberately not shown in the approval letter to the Program Administrator. An empty object (the default, and the normal case) means no exceptions were made.';

-- ---------- what is there now ----------
-- Expect zero exceptions: nothing could record one before today.
select
  count(*)                                                     as applications,
  count(*) filter (where threshold_checks     <> '{}'::jsonb)  as with_confirmations,
  count(*) filter (where threshold_exceptions <> '{}'::jsonb)  as with_exceptions
from client_applications;

-- The list worth checking back on: every engagement that went through on a
-- judgment call, and what the call was. Empty today, and it should stay
-- short -- a long list here means a threshold is set wrong, not that Rita is
-- being generous.
select
  a.company_name,
  edc.code                        as program,
  a.status,
  a.approved_at,
  e.key                           as threshold,
  e.value #>> '{}'                as reason
from client_applications a
left join econ_dev_companies edc on edc.id = a.econ_dev_company_id
cross join lateral jsonb_each(a.threshold_exceptions) as e(key, value)
order by a.approved_at desc nulls last, a.company_name;
