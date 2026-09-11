-- 118_program_setup_fee_timing.sql
--
-- Depends on 106_program_setup_fee.sql (econ_dev_companies.setup_fee) and
-- 087_engagement_closed_at.sql (clients.closed_at).
--
-- Chris/Rita review (9/11/26), confirmed by Greg: "GRE invoices bill setup
-- at the end of the engagement, not the beginning."
--
-- Today the one-time Set-Up Fee lands on the FIRST invoice an engagement
-- appears on -- program_invoicing.html adds it to every engagement whose
-- clients.setup_fee_billed is still false, including brand-new engagements
-- with no hours logged yet (that behaviour was deliberate: Greg, 8/22/26).
-- Every Program except GRE wants exactly that. GRE wants the fee held back
-- until the engagement closes.
--
-- WHY A PER-PROGRAM FLAG AND NOT A GRE SPECIAL CASE
-- Identical shape to 074_program_admin_qc_billing_model.sql, which solved
-- the same problem for Admin/QC hours: GRE bills them as performed, every
-- other Program bills them up front. That flag is bill_admin_qc_upfront and
-- defaults to true. This one is its sibling. Defaulting to true means every
-- existing Program keeps today's behaviour untouched and no past invoice is
-- retroactively contradicted; only GRE is flipped, below.
--
-- WHAT "THE END" MEANS
-- The engagement's project_status is 'closed' (clients.closed_at, stamped by
-- 087's trigger). Nothing here changes WHEN an engagement closes or what the
-- fee is -- only which invoice it first becomes eligible for. Everything
-- downstream is unchanged:
--   clients.setup_fee_billed      still the per-engagement "billed once" flag
--   econ_dev_companies.setup_fee  still the amount, same for every
--                                 engagement in the Program
--   generate_program_invoice()    still takes p_setup_fee_client_ids and
--                                 flips the flag; it never decided WHICH
--                                 engagements were eligible, the page did
--   void_program_invoice()        still un-flips from the line_items snapshot
--
-- So an engagement that closes in, say, March shows its Set-Up Fee on the
-- March Program invoice and never again. A GRE engagement that is still open
-- shows its hours but no Set-Up Fee line at all.
--
-- Safe to re-run.

alter table econ_dev_companies
  add column if not exists bill_setup_fee_upfront boolean not null default true;

comment on column econ_dev_companies.bill_setup_fee_upfront is
  'true (default): the one-time Set-Up Fee bills on the first invoice an
   engagement appears on. false: it is held back until the engagement is
   closed, and bills on the invoice for the month it closed in. GRE is the
   Program that wants false (Chris/Rita, 9/11/26).';

-- GRE bills at the end. Matched on code, the same way 070/071 set GRE's
-- billing rate. If the Program is missing this updates 0 rows and the
-- verification below says so, rather than failing.
update econ_dev_companies
set bill_setup_fee_upfront = false
where code ilike 'GRE';

-- ---------------------------------------------------------------
-- Verify. Expect GRE alone on "at close"; every other Program "up front".
-- ---------------------------------------------------------------
select
  code,
  name,
  setup_fee,
  case when bill_setup_fee_upfront then 'up front (first invoice)'
       else 'at close' end                        as setup_fee_bills,
  case when bill_admin_qc_upfront then 'up front'
       else 'as performed' end                    as admin_qc_bills
from econ_dev_companies
where not archived
order by bill_setup_fee_upfront, code;
