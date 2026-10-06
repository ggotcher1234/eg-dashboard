-- 146_role_view_override_longer_default.sql (10/6/26)   [APPLIED]
--
-- Greg: "i will rarely use the team lead and specialist views. just for a few
-- troubleshooting or to create training videos."
--
-- The 2-hour default in 145a was belt-and-braces against an override someone
-- forgot about. For a deliberate, occasional switch it is likelier to
-- interrupt a recording -- admin menus quietly reappearing mid-video -- than
-- to save anyone from anything. 12 hours still guarantees a stale override
-- cannot outlive the day, and the real protection was never the clock: it is
-- the RLS rule letting you clear your own override whatever role you wear.
--
-- role_view.js sets expires_at explicitly; this keeps the column default in
-- step so the two cannot disagree.
alter table role_view_overrides
  alter column expires_at set default (now() + interval '12 hours');
