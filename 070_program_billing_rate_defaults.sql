-- 070_program_billing_rate_defaults.sql
--
-- Greg (8/22/26) clarified the two billing rates in this app are entirely
-- separate numbers:
--   - organization_settings.hourly_rate ($95) -- what EG PAYS Team Leads
--     and Specialists (payroll cost).
--   - econ_dev_companies.billing_hourly_rate (069) -- what EG BILLS a
--     Program for that work (revenue). Defaults to $115/hr across the
--     board, except GRE, which bills at $119/hr.
-- These must never fall back to each other -- program_invoicing.html was
-- updated in the same pass to stop reading organization_settings.hourly_rate
-- at all; its only fallback now is the hardcoded $115 default.
--
-- Backfills every Program's billing_hourly_rate so it shows the correct
-- number immediately rather than sitting blank until someone opens the
-- invoice builder and it flows through the code-side default -- belt and
-- suspenders. Only touches rows that are still null, so it won't clobber
-- a rate someone's already customized through the invoice builder UI.
--
-- Safe to re-run.

update econ_dev_companies
set billing_hourly_rate = 115
where billing_hourly_rate is null;

update econ_dev_companies
set billing_hourly_rate = 119
where code ilike 'GRE';
