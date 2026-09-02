-- 106_program_setup_fee.sql
--
-- Depends on 061_client_setup_fee.sql (clients.setup_fee) and
-- 062_program_invoices.sql (clients.setup_fee_billed, generate/void
-- functions).
--
-- Greg (9/2/26) confirmed the Program Invoicing setup-fee rules:
--   1. A monthly Program invoice can contain multiple engagements.
--   2. The setup fee is a one-time fee per engagement.
--   3. The setup fee is the SAME for every engagement in a program.
--   4. The setup fee is determined by each individual program.
--
-- Rules 1 and 2 already held (program_invoices.line_items is one entry per
-- engagement; clients.setup_fee_billed makes it one-time per engagement).
-- Rules 3 and 4 did NOT: the amount lived on clients.setup_fee, editable
-- per engagement on the Cumulative Hours report, and the Program Invoice
-- screen's Setup Fee field was transient ("varies invoice to invoice, so
-- it isn't saved anywhere"). This moves the amount onto the program, the
-- same way econ_dev_companies.billing_hourly_rate already works.
--
-- After this:
--   econ_dev_companies.setup_fee  -- the one amount every engagement in
--                                    that program is billed (rules 3 + 4).
--                                    Edited/autosaved on program_invoicing.html,
--                                    shown read-only on client_cumulative_hours.html.
--   clients.setup_fee_billed      -- unchanged; still the per-engagement
--                                    "already billed once" flag (rule 2).
--   clients.setup_fee             -- now vestigial. Left in place so older
--                                    program_invoices.line_items snapshots
--                                    and any incidental reads don't break;
--                                    nothing writes it any more. Drop in a
--                                    later cleanup once nothing reads it.
--
-- generate_program_invoice() / void_program_invoice() need no change --
-- they only ever touched setup_fee_billed and the line_items snapshot,
-- never clients.setup_fee.
--
-- Safe to re-run.

alter table econ_dev_companies
  add column if not exists setup_fee numeric not null default 0;

-- Backfill: seed each program's setup_fee from the fee its own engagements
-- were already carrying. They were meant to be uniform; take the max
-- non-zero so a stray 0 on one engagement doesn't win. Programs with no
-- engagement fee on file stay at 0 for an admin to set.
update econ_dev_companies p
set setup_fee = sub.fee
from (
  select econ_dev_company_id, max(setup_fee) as fee
  from clients
  where econ_dev_company_id is not null
    and setup_fee is not null
    and setup_fee > 0
  group by econ_dev_company_id
) sub
where p.id = sub.econ_dev_company_id
  and p.setup_fee = 0;
