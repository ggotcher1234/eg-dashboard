-- 163: one table for an engagement's Program contacts  [APPLIED 10/11/26]
--
-- Greg (10/11/26), after the Discovery form came up empty: "see what it
-- would take to consolidate the two tables into one that is use by all
-- pages." Then: "do it now so we can test during this beta phase."
--
-- WHAT WAS WRONG. Two tables answered two neighbouring questions about the
-- same people:
--   client_team_partner_contacts -- who shows on the CLIENT'S dashboard as
--                                   part of their Economic Gardening team
--   client_cc_contacts           -- who is copied on this engagement's
--                                   correspondence
-- 116 split them deliberately, and that reasoning holds: ticking someone to
-- be CC'd must not also publish them to the client's page (Rita, 9/11/26).
-- What did not hold is two tables of near-identical shape, written from the
-- same screen, where a page reading the wrong one shows nothing and says
-- nothing -- which is how Discovery Call Notes sat empty for a month while
-- two contacts were ticked on the engagement.
--
-- One row per (engagement, contact), the two decisions as two flags.
create table if not exists client_partner_contacts (
  id                 uuid primary key default gen_random_uuid(),
  client_id          uuid not null references clients(id) on delete cascade,
  partner_contact_id uuid not null references econ_dev_partner_contacts(id) on delete cascade,
  on_client_team     boolean not null default false,  -- shows on the client's dashboard
  on_cc_list         boolean not null default false,  -- copied on correspondence
  sort_order         integer not null default 0,      -- the dashboard's team order
  created_at         timestamptz not null default now(),
  unique (client_id, partner_contact_id)
);

alter table client_partner_contacts enable row level security;

-- The rule both old tables carried: anyone assigned to the engagement, or an
-- Admin. A Team Lead fixes their own list without waiting on Rita.
create policy client_partner_contacts_select on client_partner_contacts
  for select using (is_super_admin() or is_assigned_to_client(client_id));
create policy client_partner_contacts_write on client_partner_contacts
  for all using (is_super_admin() or is_assigned_to_client(client_id))
       with check (is_super_admin() or is_assigned_to_client(client_id));

create index if not exists client_partner_contacts_client_idx
  on client_partner_contacts (client_id);

-- Backfill: five rows across seven engagements, and a contact in both tables
-- becomes ONE row with both flags set.
insert into client_partner_contacts (client_id, partner_contact_id, on_client_team, on_cc_list)
select client_id, partner_contact_id, bool_or(team), bool_or(cc)
from (
  select client_id, partner_contact_id, true  as team, false as cc from client_team_partner_contacts
  union all
  select client_id, partner_contact_id, false as team, true  as cc from client_cc_contacts
) both_tables
group by client_id, partner_contact_id
on conflict (client_id, partner_contact_id) do update
  set on_client_team = client_partner_contacts.on_client_team or excluded.on_client_team,
      on_cc_list     = client_partner_contacts.on_cc_list     or excluded.on_cc_list;

update client_partner_contacts p
set sort_order = t.sort_order
from client_team_partner_contacts t
where t.client_id = p.client_id and t.partner_contact_id = p.partner_contact_id;

-- FOUR FUNCTIONS repointed, by rewriting their own definitions rather than
-- by hand: three of them join the table as "ctpc", so swapping the relation
-- for a filtered subquery under the same alias leaves every other line of a
-- 200-line function untouched. accept_client_application WRITES, and its
-- insert becomes an upsert so a contact already on the row for CC gains the
-- team flag instead of being skipped.
do $do$
declare r record; d text;
begin
  for r in
    select oid, proname from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname in ('finalize_client','get_client_public_view','notify_evaluation_submitted')
  loop
    d := pg_get_functiondef(r.oid);
    d := replace(d, 'client_team_partner_contacts ctpc',
                    '(select * from client_partner_contacts where on_client_team) ctpc');
    execute d;
  end loop;

  select pg_get_functiondef(oid) into d from pg_proc
   where pronamespace = 'public'::regnamespace and proname = 'accept_client_application';
  d := replace(d,
    'insert into client_team_partner_contacts (client_id, partner_contact_id)
    values (v_client_id, v_app.program_contact_id)
    on conflict (client_id, partner_contact_id) do nothing;',
    'insert into client_partner_contacts (client_id, partner_contact_id, on_client_team)
    values (v_client_id, v_app.program_contact_id, true)
    on conflict (client_id, partner_contact_id) do update set on_client_team = true;');
  execute d;
end
$do$;

notify pgrst, 'reload schema';

-- The old tables stay, untouched and unread, until the go-live cleanup: a
-- table nobody reads costs nothing, and one dropped too early costs an
-- outage. Their comments say so.
comment on table client_team_partner_contacts is
  'SUPERSEDED 10/11/26 by client_partner_contacts.on_client_team (163).';
comment on table client_cc_contacts is
  'SUPERSEDED 10/11/26 by client_partner_contacts.on_cc_list (163).';
