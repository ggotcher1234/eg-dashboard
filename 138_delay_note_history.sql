-- 138_delay_note_history.sql   (10/4/26)
--
-- Punch list #13. The overdue note was one text column on clients
-- (delay_reason): no date, no author, and every save overwrote the last. A
-- Team Lead answering "why is this late?" in October erased the answer they
-- gave in September, so the field could never do the job Chris described --
-- replacing the spreadsheet where the history of a slipping engagement
-- lived.
--
-- Notes now go in their own table, one row per answer, and nothing
-- overwrites anything. clients.delay_reason is kept in step with the most
-- recent note so any reader still pointed at the column keeps working and
-- keeps showing the current answer.
--
-- Insert and select only. No update policy at all and delete restricted to
-- a super admin: a log that the author can quietly rewrite is not a record
-- of anything, but Greg still needs a way to clear a note typed into the
-- wrong engagement.
--
-- No DROP statements: destructive statements hang on this connection rather
-- than erroring, so everything here is "if not exists" or guarded.
--
-- Safe to re-run.

create table if not exists client_delay_notes (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid not null references clients(id) on delete cascade,
  body        text not null,
  author_id   uuid references users(id),
  created_at  timestamptz not null default now()
);

comment on table client_delay_notes is
  'Dated, attributed history of "why is this engagement late?" answers. '
  'Append-only. The most recent row is mirrored into clients.delay_reason.';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'client_delay_notes_body_len'
      and conrelid = 'client_delay_notes'::regclass
  ) then
    alter table client_delay_notes
      add constraint client_delay_notes_body_len
      check (btrim(body) <> '' and length(body) <= 300);
  end if;
end $$;

create index if not exists client_delay_notes_client_created_idx
  on client_delay_notes (client_id, created_at desc);

alter table client_delay_notes enable row level security;

-- Same reach as every other per-engagement table (client_next_steps,
-- client_research_questions): the people on the engagement, plus super
-- admins. Written as three separate policies rather than one "for all" so
-- that update is absent by construction.
do $$
begin
  if not exists (select 1 from pg_policies where schemaname='public'
                 and tablename='client_delay_notes' and policyname='client_delay_notes_select') then
    create policy client_delay_notes_select on client_delay_notes
      for select using (is_super_admin() or is_assigned_to_client(client_id));
  end if;

  if not exists (select 1 from pg_policies where schemaname='public'
                 and tablename='client_delay_notes' and policyname='client_delay_notes_insert') then
    create policy client_delay_notes_insert on client_delay_notes
      for insert with check (is_super_admin() or is_assigned_to_client(client_id));
  end if;

  if not exists (select 1 from pg_policies where schemaname='public'
                 and tablename='client_delay_notes' and policyname='client_delay_notes_delete') then
    create policy client_delay_notes_delete on client_delay_notes
      for delete using (is_super_admin());
  end if;
end $$;

-- ---------- backfill ----------
-- Whatever each engagement's single note currently says becomes its first
-- entry, so no answer already given is lost. There is no author on record
-- for these and no date beyond the row's own updated_at, which is the
-- closest honest approximation -- hence author_id null rather than guessing
-- at the Team Lead.
insert into client_delay_notes (client_id, body, author_id, created_at)
select c.id, btrim(c.delay_reason), null, coalesce(c.updated_at, now())
from clients c
where coalesce(btrim(c.delay_reason), '') <> ''
  and not exists (select 1 from client_delay_notes n where n.client_id = c.id);

-- ---------- 139 amendment (10/4/26) ----------
-- Greg, on the first cut: "there is no way to edit the comment I was
-- writing." The save fired on blur, so switching to a calendar to look up a
-- date committed a half-written note and nothing could then be done about
-- it. Saving is an explicit button now, which is the real fix, but a log
-- where a mistake is permanent is still too sharp an edge: an author can
-- remove their own note, and a super admin any of them.
--
-- Altered in place rather than dropped and recreated -- alter policy is not
-- a destructive statement and does not hang on this connection.
alter policy client_delay_notes_delete on client_delay_notes
  using (is_super_admin() or author_id = auth.uid());
