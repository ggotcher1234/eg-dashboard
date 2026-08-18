-- 052_backfill_status_since.sql
--
-- Depends on 051_engagement_status_tracking.sql.
--
-- 051's `add column ... default now()` stamped every existing client row
-- with the moment that migration ran, not when its status actually last
-- changed -- there's no real transition history to draw from, so the best
-- available stand-in is updated_at (the last time the row was touched at
-- all). Not perfect for a client whose status changed but whose record
-- hasn't been edited since, but far closer than "just now" for every
-- engagement in the system.
--
-- Safe to re-run -- always resets to the same updated_at-derived value.

update clients set status_since = coalesce(updated_at, now());
