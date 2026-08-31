-- 097_discovery_call_notes.sql
--
-- Greg (8/31/26): "add another option to Discovery Document - Create...
-- flow through all available data from the Application" followed by "I
-- want it to be a fillable form just like the Close-Out Evaluation
-- fillable form" and then "all fields in this form need to be editable."
-- These columns back the live, in-app fillable form
-- (discovery_call_notes.html): every field -- both the ones only a
-- person on the actual call can supply (participants, call link, notes)
-- and the ones normally auto-filled from the client/Application (team
-- lead, program, company info, contacts, description, business issues,
-- digital presence) -- is a real editable input, and this is where the
-- Team Lead's saved copy lives. The page still pre-fills every field
-- from live data the first time it's opened; after that, whatever the
-- Team Lead typed here takes precedence, same as any other fillable
-- form (their edits don't get overwritten by later changes elsewhere).
--
-- Safe to re-run.

alter table client_content add column if not exists discovery_call_date date;
alter table client_content add column if not exists discovery_call_participants text;
alter table client_content add column if not exists discovery_call_link text;
alter table client_content add column if not exists discovery_call_notes text;
alter table client_content add column if not exists discovery_team_lead text;
alter table client_content add column if not exists discovery_program_name text;
alter table client_content add column if not exists discovery_company_name text;
alter table client_content add column if not exists discovery_company_address text;
alter table client_content add column if not exists discovery_company_contacts text;
alter table client_content add column if not exists discovery_cc_list text;
alter table client_content add column if not exists discovery_company_description text;
alter table client_content add column if not exists discovery_business_issues text;
alter table client_content add column if not exists discovery_digital_presence text;
