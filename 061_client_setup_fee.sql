-- 061_client_setup_fee.sql
--
-- Greg (8/20/26): Chris uses a manual Excel sheet per engagement that, on
-- top of tracking cumulative hours against each specialist's budget, also
-- bills a flat one-time "Setup Fee" (his sample showed $150) alongside the
-- hourly totals. The new client_cumulative_hours.html report reproduces
-- that same layout, so clients needs somewhere to store that one-time
-- amount per engagement.
--
-- Defaults to 0 (not null) so every existing client just shows "$0.00" --
-- an editable field on the new report, not a value anyone has to backfill.
--
-- Safe to re-run.

alter table clients
  add column if not exists setup_fee numeric not null default 0;
