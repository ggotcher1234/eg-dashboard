-- 179_personal_discovery_guide.sql
--
-- Greg (10/26/26), on the question guides added the same day: "some TL's
-- may have their own list of questions they like to ask while others just
-- like to wing it. so the guide needs to be selectable, editable and
-- dismissable."
--
-- Selectable was already there (five built-in sets in a picker). These two
-- columns carry the other two.
--
-- discovery_guide        -- this person's OWN question set, if they saved
--                           one. Same markdown-lite the notes themselves
--                           use ("**bold**", "- " bullets), so it goes
--                           through notesTextToHtml on the way in and
--                           notesHtmlToText on the way out, exactly like
--                           the note it was saved from. No second format,
--                           no second parser.
--
--                           It is saved FROM the notes field rather than
--                           typed into a template editor: a Team Lead
--                           inserts a built-in set, deletes what they never
--                           ask, adds their own, and presses Save. The
--                           editor they already know is the template
--                           editor, which is why there is no new screen
--                           here.
--
-- discovery_guide_hidden -- the wing-it case. Hides the picker row for this
--                           person on every engagement and every machine.
--                           On the profile rather than in localStorage
--                           because it follows the person, not the browser,
--                           and because a preference that quietly resets on
--                           a new laptop is worse than no preference.
--                           Recoverable: the row leaves a small "Guides"
--                           link behind rather than vanishing outright.
--
-- Both are the user's own, like About or their phone -- no Admin gate.
-- users_update_self already allows a person to write their own row, and
-- enforce_super_admin_user_fields only guards role and organization_id, so
-- nothing else has to change.
--
-- Safe to re-run.

alter table users add column if not exists discovery_guide text;
alter table users add column if not exists discovery_guide_hidden boolean not null default false;

comment on column users.discovery_guide is
  'This person''s own discovery-call question set, saved from the notes field. Markdown-lite, same as client_content.discovery_call_notes. Null means they use the built-in sets.';
comment on column users.discovery_guide_hidden is
  'True hides the question-guide picker on the Discovery Call Notes form for this person. For Team Leads who run the call without a script.';

-- Check: both columns present, nobody opted out yet.
select count(*) filter (where discovery_guide is not null) as have_own_guide,
       count(*) filter (where discovery_guide_hidden)      as hid_the_picker
from users;
