-- 071_force_reset_billing_rates.sql
--
-- Greg (8/22/26) reported still seeing $95/hr on the invoice builder after
-- 069/070. Most likely explanation: while we were debugging the previous
-- version of program_invoicing.html, the Hourly Rate field auto-saves to
-- econ_dev_companies.billing_hourly_rate on change, and a stray $95 got
-- written to a Program's row before the bug (stale value in the field) was
-- fixed -- 070's backfill only touched rows that were still NULL, so it
-- wouldn't have corrected an already-non-null bad value.
--
-- This one is unconditional -- it resets EVERY Program's billing rate to
-- $115 (then $119 for GRE), regardless of what's currently stored, as a
-- clean known-good baseline. Safe to re-run; run this AFTER 069 and 070.

update econ_dev_companies
set billing_hourly_rate = 115;

update econ_dev_companies
set billing_hourly_rate = 119
where code ilike 'GRE';
