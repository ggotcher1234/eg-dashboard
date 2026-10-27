-- 180_roster_linkedin.sql
--
-- Greg (10/27/26): "We don't need this field about how their letters are
-- signed anymore. what i would like in it's place is a LinkedIn Logo with
-- an edit button that allows them to add their linkedin address."
--
-- The note it replaces explained where a letter's sign-off comes from. It
-- was accurate and nobody needed telling twice, so the space is better
-- spent on something with a value in it.
--
-- A roster LinkedIn address is worth having for its own sake: Economic
-- Gardening specialists are contractors with their own practices, Team
-- Leads introduce them to clients, and outbound work runs through Sales
-- Navigator all day. Knowing where a specialist is on LinkedIn saves
-- looking them up.
--
-- The person's own, like About or their phone -- no Admin gate.
-- users_update_self already lets someone write their own row and
-- enforce_super_admin_user_fields guards only role and organization_id.
--
-- Stored as typed and normalised in the page: a bare "linkedin.com/in/x"
-- or an "@handle" is what people actually paste, and refusing those on a
-- technicality would just mean the field stays empty.
--
-- Safe to re-run.

alter table users add column if not exists linkedin_url text;

comment on column users.linkedin_url is
  'This person''s LinkedIn profile address, shown on their Roster card. Their own, like About or their phone.';

-- Check: column present, and how many have filled it in.
select count(*) as roster_rows,
       count(linkedin_url) as have_linkedin
from users;
