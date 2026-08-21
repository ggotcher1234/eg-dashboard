-- 062_program_invoices.sql
--
-- Greg (8/20/26): building the "Program Invoice" report -- the real monthly
-- bill NCEG sends to each funding Program (e.g. Virginia Economic
-- Development Partnership) for that month's activity across every client
-- engagement that Program funds. Chris's real invoices (see the
-- VA-May-2026-30.pdf reference he shared) are numbered sequentially
-- ("2026-30"), grouped by client engagement, with a Team Lead / Market
-- Research / GIS / Admin / Quality Control / Set-Up Fees line per client, a
-- subtotal per client, and one Total Due.
--
-- Each generated invoice is snapshotted into line_items (jsonb) rather than
-- recomputed live from time_entries every time it's reopened -- so if a
-- time entry gets edited later, invoices already sent to a Program don't
-- silently change out from under Greg.
--
-- Numbering: Greg confirmed invoice numbers should be tracked and never
-- repeat (AskUserQuestion, 8/20/26). "2026-30" reads as a single running
-- sequence per calendar year across every Program (not reset per program),
-- which is what generate_program_invoice() below computes.
--
-- Set-Up Fee: Greg also confirmed (same round of questions) that a client's
-- one-time setup_fee (061_client_setup_fee.sql) should be auto-included the
-- first time that client shows any billable activity on a Program invoice,
-- then never again -- hence the new setup_fee_billed flag on clients,
-- flipped atomically by the same function that creates the invoice.
--
-- Admin/Quality Control follow the same "bill once" shape as the Set-Up
-- Fee, not the "bill actual logged hours every month" shape that Team
-- Lead/Market Research/GIS/Digital Marketing/Watering Holes use -- per the
-- app-wide sunk-cost convention (client_workspace.html), Admin/QC hours
-- are never logged in time_entries; the whole hours_allotted amount is
-- owed once, whenever the engagement's first invoice goes out (see
-- CAF2CODE/Third Shift Coffee in the VA-May-2026-30.pdf reference, both
-- billing Admin + Quality Control + Set-Up Fee together in what's clearly
-- their first invoice). sunk_cost_billed on client_assignments tracks that
-- per assignment, the same way setup_fee_billed tracks it per client.
--
-- Safe to re-run.

create table if not exists program_invoices (
  id                  uuid primary key default gen_random_uuid(),
  organization_id     uuid not null references organizations(id) on delete cascade,
  econ_dev_company_id uuid not null references econ_dev_companies(id),
  invoice_number      text not null unique,
  invoice_date        date not null default current_date,
  billing_month       text not null, -- 'YYYY-MM', the "Engagements <Month> <Year>" period being billed
  total_due           numeric not null default 0,
  -- Snapshot of exactly what was billed: one entry per client engagement,
  -- e.g. { client_id, client_name, lines: [{ label, qty, rate, amount }],
  -- setup_fee: 150 or null, subtotal }. This is what both the on-screen
  -- reprint and the printed invoice render from -- never live-recomputed.
  line_items          jsonb not null default '[]'::jsonb,
  created_by          uuid references users(id),
  created_at          timestamptz not null default now(),
  voided              boolean not null default false,
  voided_at           timestamptz,
  void_reason         text
);

create index if not exists idx_program_invoices_program on program_invoices(econ_dev_company_id);
create index if not exists idx_program_invoices_org on program_invoices(organization_id);
create index if not exists idx_program_invoices_month on program_invoices(billing_month);

alter table program_invoices enable row level security;

-- Admin only, matching Invoicing Report / Cumulative Hours -- this is
-- billing data sent to outside funders, not something every Team Lead
-- should be able to browse or regenerate.
drop policy if exists program_invoices_admin_all on program_invoices;
create policy program_invoices_admin_all on program_invoices
  for all
  using ( is_super_admin() )
  with check ( is_super_admin() );

-- Tracks whether a client's one-time Set-Up Fee has already appeared on a
-- generated Program invoice, so it's never billed twice.
alter table clients add column if not exists setup_fee_billed boolean not null default false;

-- Tracks whether an Admin/Quality Control assignment's one-time
-- hours_allotted has already been billed on a Program invoice (see note
-- above -- these two specialties bill their full allotment once, not
-- monthly actuals).
alter table client_assignments add column if not exists sunk_cost_billed boolean not null default false;

-- Creates the next invoice in sequence for a Program/month and, in the same
-- transaction, marks setup_fee_billed / sunk_cost_billed for whatever
-- clients/assignments this invoice includes them for. security definer +
-- an explicit admin check (rather than relying on RLS alone) because it
-- also needs to write to `clients` and `client_assignments`, which
-- ordinary Team Leads have narrower access to.
create or replace function generate_program_invoice(
  p_organization_id      uuid,
  p_econ_dev_company_id  uuid,
  p_billing_month        text,
  p_invoice_date         date,
  p_line_items           jsonb,
  p_total_due            numeric,
  p_setup_fee_client_ids uuid[] default '{}',
  p_sunk_cost_assignment_ids uuid[] default '{}'
)
returns program_invoices
language plpgsql
security definer
set search_path = public
as $$
declare
  v_year text;
  v_next_seq int;
  v_invoice_number text;
  v_row program_invoices;
begin
  if not is_super_admin() then
    raise exception 'Only Admins can generate Program invoices.';
  end if;

  v_year := to_char(p_invoice_date, 'YYYY');

  -- Serializes concurrent generation (two admins clicking "Generate" at the
  -- same moment) so the same invoice number can never be handed out twice.
  perform pg_advisory_xact_lock(hashtext('program_invoice_seq_' || v_year));

  select coalesce(max((split_part(invoice_number, '-', 2))::int), 0) + 1
  into v_next_seq
  from program_invoices
  where invoice_number like (v_year || '-%');

  v_invoice_number := v_year || '-' || v_next_seq;

  insert into program_invoices (
    organization_id, econ_dev_company_id, invoice_number, invoice_date,
    billing_month, total_due, line_items, created_by
  ) values (
    p_organization_id, p_econ_dev_company_id, v_invoice_number, p_invoice_date,
    p_billing_month, p_total_due, p_line_items, auth.uid()
  )
  returning * into v_row;

  if array_length(p_setup_fee_client_ids, 1) > 0 then
    update clients set setup_fee_billed = true
    where id = any(p_setup_fee_client_ids);
  end if;

  if array_length(p_sunk_cost_assignment_ids, 1) > 0 then
    update client_assignments set sunk_cost_billed = true
    where id = any(p_sunk_cost_assignment_ids);
  end if;

  return v_row;
end;
$$;

grant execute on function generate_program_invoice(uuid, uuid, text, date, jsonb, numeric, uuid[], uuid[]) to authenticated;

-- Lets an Admin undo a mistaken invoice (wrong month/program picked, etc.)
-- without deleting the row -- keeps the number permanently retired rather
-- than reusable, and un-flips setup_fee_billed / sunk_cost_billed for
-- anything that was only ever billed on this now-voided invoice, so it's
-- picked back up the next time an invoice is generated. Relies on each
-- line_items client entry carrying "setup_fee" (amount or null) and each
-- line within it carrying "assignment_id" + "is_sunk_cost" (see
-- program_invoicing.html's buildLineItems()).
create or replace function void_program_invoice(p_invoice_id uuid, p_reason text default null)
returns program_invoices
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row program_invoices;
  v_client_id uuid;
  v_assignment_id uuid;
begin
  if not is_super_admin() then
    raise exception 'Only Admins can void Program invoices.';
  end if;

  update program_invoices
  set voided = true, voided_at = now(), void_reason = p_reason
  where id = p_invoice_id
  returning * into v_row;

  if v_row.id is null then
    raise exception 'Invoice not found.';
  end if;

  for v_client_id in
    select (elem->>'client_id')::uuid
    from jsonb_array_elements(v_row.line_items) elem
    where (elem->>'setup_fee') is not null
  loop
    update clients set setup_fee_billed = false where id = v_client_id;
  end loop;

  for v_assignment_id in
    select (line->>'assignment_id')::uuid
    from jsonb_array_elements(v_row.line_items) elem,
         jsonb_array_elements(elem->'lines') line
    where (line->>'is_sunk_cost')::boolean is true
  loop
    update client_assignments set sunk_cost_billed = false where id = v_assignment_id;
  end loop;

  return v_row;
end;
$$;

grant execute on function void_program_invoice(uuid, text) to authenticated;
