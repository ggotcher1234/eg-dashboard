-- 176_roster_email_signature.sql
--
-- Greg (10/23/26): "now we want to add a custom signature block for each of
-- the emails that the system creates. my idea is to put a signature block in
-- the Roster cards and have the create email button pull the roster card
-- signature."
--
-- Two columns on users, and the three decisions behind them:
--
-- 1. Plain text. Every letter the dashboard composes travels in a mailto
--    body, and RFC 6068 makes that plain text -- no logo, no styled links.
--    The signature sits under the letter's own closing line ("Thank you,",
--    "Best regards,"), so it starts at the name.
--
-- 2. use_dashboard_signature, default true. Outlook and Gmail both add the
--    sender's own signature to a mailto draft, and ours would land above
--    theirs. Anyone that happens to turns this off once; their letters then
--    end at the closing line and their client supplies the rest. Greg chose
--    a per-person switch over signing everyone and making them delete one.
--
-- 3. The signature belongs to the person a letter is written AS, not to
--    whoever is at the keyboard -- the Scheduling Letter is the Team Lead's
--    even when an Admin opens it, the research email is the assigned
--    specialist's. Greg settled that one too.
--
-- Nothing is written into the column here: a blank signature falls back to
-- the name, title and phone already on the profile, so every letter is
-- signed from the day this ships whether or not anyone has typed one.

alter table users add column if not exists email_signature text;
alter table users add column if not exists use_dashboard_signature boolean not null default true;

comment on column users.email_signature is
  'Greg (10/23/26): "add a custom signature block for each of the emails that the system creates ... put a signature block in the Roster cards and have the create email button pull the roster card signature." Plain text, because every letter the dashboard composes travels in a mailto body, which is plain text under RFC 6068. Appended under each letter''s own closing line. Blank means fall back to name, title and phone from this profile.';

comment on column users.use_dashboard_signature is
  'Off for people whose own mail client already signs them -- Outlook and Gmail add a signature to a mailto draft, and ours would land above theirs. Off means the letter ends at its closing line and their client supplies the rest.';
