-- 150: a per-year starting point for Program invoice numbers.
--
-- Rita (10/7/26): "When we go live can we start with a specific program
-- invoice number. Our invoice numbers start with the year and then
-- consecutive. We are already up to 2026-57."
--
-- The format in 062 was already hers -- YYYY-N, next = highest that year + 1.
-- What was missing was any way to START a year partway through, because the
-- sequence is derived purely from the rows present. Two consequences, both
-- fixed by a floor rather than by seeding a fake invoice:
--   * NCEG's first EGDB invoice would be 2026-9 (eight test invoices exist),
--     not 2026-58, and would collide with numbers already issued outside the
--     system.
--   * Deleting those test rows at go-live would silently reset the next
--     number to 1. A floor is immune to that -- it is a stated intent, not a
--     side effect of which rows happen to be there.
--
-- One row per year, so January 2027 does not inherit 2026's offset.

create table if not exists program_invoice_number_floor (
  invoice_year text primary key,
  first_seq    int  not null check (first_seq >= 1),
  note         text,
  set_by       uuid references users(id),
  set_at       timestamptz not null default now()
);

comment on table program_invoice_number_floor is
  'Earliest sequence number generate_program_invoice() may issue for a given year. Lets NCEG continue an invoice series started outside EGDB.';

alter table program_invoice_number_floor enable row level security;

-- Existence-checked rather than "drop policy if exists": a DROP of any kind
-- hangs for 180s through the MCP connection this is applied over (see 145).
do $$
begin
  if not exists (
    select 1 from pg_policies
     where schemaname = 'public'
       and tablename  = 'program_invoice_number_floor'
       and policyname = 'invoice_floor_admin_read'
  ) then
    create policy invoice_floor_admin_read on program_invoice_number_floor
      for select using (is_super_admin());
  end if;

  if not exists (
    select 1 from pg_policies
     where schemaname = 'public'
       and tablename  = 'program_invoice_number_floor'
       and policyname = 'invoice_floor_admin_write'
  ) then
    create policy invoice_floor_admin_write on program_invoice_number_floor
      for all using (is_super_admin()) with check (is_super_admin());
  end if;
end $$;

-- 2026 continues NCEG's own series. 57 issued outside EGDB, so the first one
-- generated here is 2026-58.
insert into program_invoice_number_floor (invoice_year, first_seq, note)
values ('2026', 58, 'Continues the series NCEG issued outside EGDB; 2026-57 was the last of those.')
on conflict (invoice_year) do update
  set first_seq = excluded.first_seq,
      note      = excluded.note,
      set_at    = now();
