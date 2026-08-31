-- 097_discovery_call_notes.sql
--
-- Greg (8/31/26): "add another option to Discovery Document - Create...
-- flow through all available data from the Application" followed by "I
-- want it to be a fillable form just like the Close-Out Evaluation
-- fillable form." Replaces the earlier docx-download approach with a
-- live, in-app fillable form (discovery_call_notes.html) that a Team
-- Lead opens, fills in, and saves directly -- these 4 columns hold what
-- only a person on the actual call can supply (everything else on the
-- form -- company info, contacts, team lead, program -- is pulled live
-- from existing tables, same as before).
--
-- Safe to re-run.

alter table client_content add column if not exists discovery_call_date date;
alter table client_content add column if not exists discovery_call_participants text;
alter table client_content add column if not exists discovery_call_link text;
alter table client_content add column if not exists discovery_call_notes text;
