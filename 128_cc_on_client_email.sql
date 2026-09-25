-- 128_cc_on_client_email.sql   (9/25/26)
--
-- Greg (9/25/26): "Rita requested to be copied on all client correspondence
-- too."
--
-- WHY A FLAG AND NOT A SECOND NAME IN THE CODE
-- Chris is on the CC line today because client_control_center.html carries
-- this, literally:
--
--   const WELCOME_CC_MATCH = (u) =>
--     /^cgibbons@/i.test(u.email || "") || /\bchris(topher)?\b.*\bgibbons\b/i.test(u.full_name || "");
--
-- It works, but it is a person's name compiled into a web page. Adding Rita
-- the same way means a second regex, a third when the next person asks, and a
-- deploy every time somebody leaves. It also fails silently and strangely: it
-- matched Chris's PERSONAL account as readily as his work one, so which
-- address ended up on the CC line depended on the order the roster came back
-- in.
--
-- So it becomes what it always was -- a property of a person, ticked on their
-- profile. Rita can be added, or removed, by an Admin in the Roster with no
-- code change and no deploy.
--
-- SCOPE. This is the internal "keep me in the loop" list, and it is separate
-- from the two CC ideas that already exist, deliberately:
--   * client_cc_list        -- people at or around the CLIENT, per engagement;
--   * client_cc_contacts    -- PROGRAM contacts picked when the engagement was
--                              accepted (and, since 9/25/26, the Program
--                              Administrator, who is always included);
--   * users.cc_on_client_email (this) -- EG staff who want a copy of
--                              everything, on every engagement.
-- Three lists, three different questions. Merging them would mean answering
-- one of those questions in a place that cannot see the others.
--
-- Safe to re-run.

alter table users
  add column if not exists cc_on_client_email boolean not null default false;

comment on column users.cc_on_client_email is
  'This person is CC''d on client correspondence composed in the app, on every engagement. Ticked per person on the Roster profile. Replaces the hardcoded Chris Gibbons match that lived in client_control_center.html until 9/25/26.';

-- ---------- seed: keep today's behaviour exactly ----------
-- Match the rule the page uses right now, so nobody who is on the CC line
-- today falls off it. Rita is NOT seeded here -- her address is not something
-- to guess at in a migration, and the listing below makes her one tick away.
do $$
declare
  n int;
begin
  update users
     set cc_on_client_email = true
   where archived_at is null
     and (email ilike 'cgibbons@%' or full_name ~* '\mchris(topher)?\M.*\mgibbons\M');
  get diagnostics n = row_count;
  raise notice 'Carried % existing CC recipient(s) over from the hardcoded rule.', n;
  raise notice 'Rita is not seeded -- tick "CC on client correspondence" on her Roster profile.';
end $$;

-- Who is on the list now, and who could be. Tick anyone else on the Roster.
select
  full_name,
  email,
  role::text            as eg_role,
  cc_on_client_email    as cc_on_client_email,
  hidden_from_roster,
  archived_at is not null as archived
from users
where role = 'super_admin' or cc_on_client_email
order by cc_on_client_email desc, full_name;
