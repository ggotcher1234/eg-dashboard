-- 069_program_billing_rate.sql
--
-- Greg (8/22/26): the Program Invoice builder was billing every Program at
-- the same single organization_settings.hourly_rate used to pay specialists
-- -- but in reality different Programs are billed at different rates (Greg
-- mentioned $115 vs $119), and the billing rate isn't necessarily the same
-- number as payroll at all. Giving each Program its own optional saved
-- rate lets program_invoicing.html remember "Program X bills at $119"
-- without touching payroll's org-wide rate.
--
-- Nullable on purpose: a Program with no rate saved yet just falls back to
-- organization_settings.hourly_rate, same behavior as before this migration.
--
-- Safe to re-run.

alter table econ_dev_companies add column if not exists billing_hourly_rate numeric;
