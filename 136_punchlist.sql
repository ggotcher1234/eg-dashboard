-- 136: the shared review punch list, as a page on egdb.netlify.app.
--      (APPLIED 10/3/26)
--
-- It started as a claude.ai artifact, which meant Chris and Rita each
-- needed a Claude account and an invitation before the link would open.
-- Greg (10/3/26): "that will be too confusing for chris. let's change this
-- from an artifact to an html app with the same url that will not need a
-- Claude account to access."
--
-- DELIBERATELY OPEN (Greg's call, 10/3/26): anyone who reaches /punchlist
-- can read and change it. No sign-in, no passcode. The alternative cost
-- Chris more than the content is worth protecting. Keep that in mind
-- before putting anything here that would matter in a stranger's hands:
-- it is a list of internal tasks. Nothing in these tables joins to
-- clients, users or applications, so a bad actor's reach ends at the list.
-- The length and status constraints below are the guard rails that
-- replaces authentication: a runaway paste or a junk status fails at the
-- door rather than becoming a row nobody can read past.
--
-- Written with no DROP or DELETE statements: both are currently refused on
-- the way into this database (they hang rather than erroring), so
-- everything here is create-if-not-exists or create-or-replace.

create table if not exists punchlist_items (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  note        text,
  owner       text,
  source      text,
  status      text not null default 'ready',
  sort_order  integer not null default 0,
  created_by  text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  -- Only the five statuses the page groups by: a typo would otherwise
  -- drop an item out of every group and off the page entirely.
  constraint punchlist_items_status_chk
    check (status in ('decide','waiting','ready','data','done')),
  constraint punchlist_items_len_chk
    check (length(title) between 1 and 300
       and (note is null or length(note) <= 4000)
       and (owner is null or length(owner) <= 80)
       and (created_by is null or length(created_by) <= 80))
);

create table if not exists punchlist_comments (
  id          uuid primary key default gen_random_uuid(),
  item_id     uuid not null references punchlist_items(id) on delete cascade,
  author      text,
  body        text not null,
  created_at  timestamptz not null default now(),
  constraint punchlist_comments_len_chk
    check (length(body) between 1 and 4000
       and (author is null or length(author) <= 80))
);

create index if not exists punchlist_comments_item_idx on punchlist_comments(item_id);
create index if not exists punchlist_items_sort_idx on punchlist_items(sort_order);

alter table punchlist_items enable row level security;
alter table punchlist_comments enable row level security;

create policy punchlist_items_open on punchlist_items
  for all to anon, authenticated using (true) with check (true);

create policy punchlist_comments_open on punchlist_comments
  for all to anon, authenticated using (true) with check (true);

grant usage on schema public to anon;
grant select, insert, update, delete on punchlist_items to anon, authenticated;
grant select, insert, update, delete on punchlist_comments to anon, authenticated;

-- updated_at is what the page shows as "changed just now", so it has to
-- move on its own; an open page cannot rely on every writer setting it.
create or replace function punchlist_touch() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace trigger trg_punchlist_touch before update on punchlist_items
  for each row execute function punchlist_touch();

-- The 20 opening items were inserted separately, from the list built
-- during the 10/2 review. They are data, not schema, so they are not
-- repeated here; the board is the record now.
--
-- Verified after applying, running as the anon role: 20 items readable,
-- a status update accepted, a comment inserted and read back, and a
-- status outside the five refused by the check constraint.
