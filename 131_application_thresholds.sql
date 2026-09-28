-- 131_application_thresholds.sql   (9/28/26)
--
-- Rita's five thresholds, from the email template she sends the Program
-- Administrator once NCEG has reviewed an application:
--
--     Thresholds                    Passed
--   1. Full Contact Info            Yes
--   2. CEO Listed                   Yes
--   3. 10+ Employees                Yes
--   4. $1 M + sales                 Yes
--   5. Sell to external Markets     Yes
--
-- WHY THIS IS ONE COLUMN AND NOT FIVE
-- Five booleans would be five migrations the next time the list changes, and
-- the list HAS changed -- these five arrived on 9/28/26 and were not in the
-- procedure as described three days earlier. A jsonb object keyed by a stable
-- id per threshold lets the wording move, lets a sixth be added, and keeps
-- what was actually confirmed on the applications already through the door.
--
-- Shape: {"contact_info": true, "ceo_listed": true, ...}. A key that is
-- absent means nobody has confirmed that threshold; the page treats absent
-- and false identically for gating, and stores only what was ticked.
--
-- WHAT IT IS NOT
-- It is not the ANSWER to each threshold -- four of the five are already
-- answered by the application itself (the public form asks the 10-100 FTE,
-- $1-50M sales and external-markets questions outright, and requires the
-- officer's name, title, email and phone). The page shows those answers
-- beside each row. This column records that a person LOOKED and agreed,
-- which is the part no query can supply, and the part Rita is putting her
-- name to when she writes to the Program.
--
-- Deliberately no approved_at-style stamp per row. Who confirmed and when is
-- already answered for the application as a whole -- the application cannot
-- be accepted until all five are ticked, and accepting is recorded. A
-- timestamp per checkbox would be five more facts nobody will ever read.
--
-- Safe to re-run.

alter table client_applications
  add column if not exists threshold_checks jsonb not null default '{}'::jsonb;

comment on column client_applications.threshold_checks is
  'Rita''s five review thresholds, keyed by a stable id -- contact_info, ceo_listed, employees_10_plus, sales_1m_plus, external_markets -- each true once confirmed on the Accept form. An absent key means not yet confirmed. All five must be true before an application can be accepted. The wording of each threshold lives in client_applications.html, not here, so it can change without a migration.';

-- ---------- what this does to applications already in flight ----------
-- Nothing is backfilled. An application accepted before today went through
-- the process as it stood then, and marking its thresholds "confirmed" would
-- be recording a review that never happened. Only PENDING applications are
-- affected, and those genuinely do now need the five ticks -- which is the
-- point of the change.
select
  status,
  count(*)                                                as applications,
  count(*) filter (where threshold_checks <> '{}'::jsonb) as with_checks
from client_applications
group by status
order by status;

-- The pending ones, with the answers the form already gives for four of the
-- five. This is the same data the Accept form will show beside each row --
-- worth a look before anyone ticks anything, to see whether the pre-fill is
-- landing where you would expect.
select
  a.company_name,
  edc.code                                    as program,
  (a.primary_officer_name is not null
     and a.primary_officer_title is not null
     and a.primary_officer_email is not null
     and a.primary_officer_phone is not null) as contact_info_complete,
  a.primary_officer_title                     as officer_title,
  a.fte_range_10_to_100                       as ten_plus_fte_answer,
  a.fte_2025,
  a.sales_1_to_50m                            as sales_1m_answer,
  a.revenue_2025,
  a.sales_primarily_external                  as external_markets_answer
from client_applications a
left join econ_dev_companies edc on edc.id = a.econ_dev_company_id
where a.status = 'pending'
order by a.submitted_at desc;
