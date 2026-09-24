-- 127_county_and_split_billing.sql   (9/24/26)
--
-- Rita (9/24/26): "I just thought of another billing requirement that we have
-- for GRE. We send them 2 invoices: one for all engagements in Monroe County
-- and the other for the rest of the engagements in all other counties."
--
-- THE BLOCKER IS NOT THE INVOICE, IT IS THE DATA
-- The public application form asks for County -- it is a required field, and
-- it lands on client_applications.address as
-- {street, city, state, postal, county}. But accept_client_application()
-- flattens that address down to "street, city state postal" before writing it
-- to clients.address (110, lines 57-59). The county is dropped on the floor at
-- the moment an application becomes an engagement, and nothing downstream has
-- ever had it. So today there is no way to tell a Monroe County engagement
-- from any other, and no invoice split is possible.
--
-- This migration is the data half. It:
--   1. gives clients a county of its own -- a real column, not a substring of
--      the address, so it can be filtered on and corrected;
--   2. recovers it for existing engagements from the application each one came
--      from (client_applications.client_id is the link);
--   3. keeps it filled in from now on, with a trigger rather than a rewrite of
--      accept_client_application() -- that function is 150 lines doing a dozen
--      unrelated things, and restating it here to change one value would be a
--      standing risk of drift for no benefit;
--   4. adds the two columns the split itself needs.
--
-- It does NOT change any invoice. Generating the second invoice is done in
-- program_invoicing.html, which already builds its own line items and calls
-- generate_program_invoice() -- so a split is two calls rather than a new
-- function, and invoice numbering is already serialised behind an advisory
-- lock, so the two invoices get consecutive numbers safely.
--
-- Safe to re-run.

-- ---------- 1. county on the engagement ----------
alter table clients add column if not exists county text;

comment on column clients.county is
  'County this engagement sits in. Auto-filled from the application it came from (the form collects it); editable afterwards on Company Info. Used to split a Program''s monthly invoice -- see econ_dev_companies.invoice_split_county.';

-- ---------- 2. the split setting, per Program ----------
-- Nullable, and null means what it has always meant: one invoice per program
-- per month. Set it to a county name (e.g. 'Monroe') and that Program bills in
-- two: engagements in that county, and everything else.
--
-- A single named county rather than "one invoice per county" is deliberate --
-- Rita asked for exactly two invoices, and grouping by every county present
-- would hand GRE one per county in a given month, which is not the same thing.
alter table econ_dev_companies add column if not exists invoice_split_county text;

comment on column econ_dev_companies.invoice_split_county is
  'When set, this Program''s monthly invoice is generated as two: one for engagements whose clients.county matches this value, one for all the others. Null (the default) = a single invoice, the original behaviour.';

-- ---------- 3. which half an invoice is ----------
-- Without this the two invoices for a month are indistinguishable in the Past
-- Invoices list and on the printout -- same program, same month, same shape.
alter table program_invoices add column if not exists billing_segment text;

comment on column program_invoices.billing_segment is
  'Which half of a split invoice this is, e.g. ''Monroe County'' or ''All other counties''. Null on an ordinary single invoice, including every invoice generated before 9/24/26.';

-- ---------- 4. recover the county for existing engagements ----------
do $$
declare
  n_filled int;
begin
  update clients c
     set county = nullif(trim(a.address->>'county'), '')
    from client_applications a
   where a.client_id = c.id
     and c.county is null
     and nullif(trim(a.address->>'county'), '') is not null;
  get diagnostics n_filled = row_count;
  raise notice 'Recovered county for % engagement(s) from their applications.', n_filled;
end $$;

-- ---------- 5. keep it filled in from here on ----------
-- accept_client_application() sets client_applications.client_id at the moment
-- it creates the engagement, so watching for that is the same instant, without
-- touching the function itself. coalesce, so a county typed by hand is never
-- overwritten by a re-run or a late edit to the application.
create or replace function copy_application_county_to_client()
returns trigger
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
begin
  if new.client_id is not null
     and (old.client_id is null or old.client_id is distinct from new.client_id)
     and nullif(trim(new.address->>'county'), '') is not null
  then
    update clients
       set county = coalesce(county, nullif(trim(new.address->>'county'), ''))
     where id = new.client_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_copy_application_county on client_applications;
create trigger trg_copy_application_county
  after update on client_applications
  for each row
  execute function copy_application_county_to_client();

-- ---------- 6. what still needs a human ----------
-- An engagement created by hand, or one whose applicant left County blank, has
-- nothing to recover from. These are the rows Greg and Rita have to fill in on
-- Company Info before a split invoice can be trusted -- an engagement with no
-- county falls into "all other counties" by default, which is silently wrong
-- if it is actually in Monroe.
select
  edc.name                    as program,
  c.name                      as engagement,
  coalesce(c.county, '(none)') as county,
  c.project_status
from clients c
left join econ_dev_companies edc on edc.id = c.econ_dev_company_id
where c.county is null
order by edc.name nulls last, c.name;

-- And the counties we do have, per Program -- check the spelling of the one
-- you are about to type into invoice_split_county against this.
select
  coalesce(edc.name, '(no program)') as program,
  coalesce(c.county, '(none)')       as county,
  count(*)                           as engagements
from clients c
left join econ_dev_companies edc on edc.id = c.econ_dev_company_id
group by 1, 2
order by 1, 2;
