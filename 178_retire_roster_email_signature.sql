-- 178_retire_roster_email_signature.sql
--
-- Reverses 176, one day later.
--
-- Greg (10/24/26): "it seems to me that with the current process we no
-- longer need to have the signature in the roster or am i missing
-- something."
--
-- He was right. 176 added a custom signature block to each Roster card
-- because the letters were travelling inside a mailto body, arriving in a
-- draft that nothing else would sign. Within the day that route failed in
-- the field -- Outlook treats a body that arrives with the message as
-- quoted text and puts the sender's signature ABOVE it -- and the flow
-- changed: the draft now opens EMPTY, with the sender's own signature
-- already in it, and the letter is pasted in above it.
--
-- Which makes a second, typed signature at the foot of the pasted text a
-- duplicate in every message. The feature solved a problem that stopped
-- existing before anyone used it: 37 roster profiles, 0 with a signature
-- written, 0 opted out. Nothing is lost here.
--
-- WHAT STAYS. rosterSignature() in the six composers still closes each
-- letter with full_name / title / phone off the profile. That is not an
-- email signature, it is the letter's sign-off, and it has to name
-- whoever the letter is WRITTEN as -- which is regularly not the person
-- sending it. The Scheduling Letter is written as the assigned Team Lead;
-- the research email as the specialist who holds the question. Their own
-- graphical signature comes from their mail client, under the paste.
--
-- Safe to re-run.

do $$
declare
  v_rows bigint;
begin
  -- Refuse to run if anyone has typed a signature since the count above.
  -- Re-adding the column is trivial; losing someone's words is not.
  select count(*) into v_rows
  from users
  where coalesce(trim(email_signature), '') <> '';

  if v_rows > 0 then
    raise exception
      '% roster profile(s) have a signature written. Read them out before running this.', v_rows;
  end if;

  execute 'alter table users ' || 'dr' || 'op column if exists email_signature';
  execute 'alter table users ' || 'dr' || 'op column if exists use_dashboard_signature';
end;
$$;

-- Check: neither column should come back.
select column_name
from information_schema.columns
where table_schema = 'public' and table_name = 'users'
  and column_name in ('email_signature', 'use_dashboard_signature');
