-- 103_controlling_doc_client_response.sql
--
-- Depends on:
--   033_research_questions.sql  -- client_research_questions, research_area_type
--   078_evaluation_responses.sql -- notifications table + the notify-trigger
--                                   pattern this copies
--   101_controlling_doc_question_fields.sql -- background / ranking /
--                                             customer_notes columns
--
-- Greg (9/1/26): "create a link to this document so we can email it to the
-- client... write a nice email requesting their feedback on the CD, give
-- them the link, and when they fill it out or just open and hit submit it
-- should post back in our system and alert the team via the bell that the
-- CD has been finalized by the customer."
--
-- This is the Controlling Document twin of the Close-Out Evaluation link
-- (077-080): a per-client public page (controlling_document_public.html)
-- the client opens with no login, where they rank each research question
-- and leave notes/changes, submitting straight to the DB through the
-- public-submit-controlling-doc Edge Function (service-role writer, same
-- "no session to attach the write to" model as public-submit-evaluation).
--
-- Three parts, matching 078:
--   1. client_controlling_doc_responses -- one row per client submission.
--      Holds respondent name/email, an overall notes box, and a
--      question_responses jsonb array [{question_id, question, ranking,
--      notes}] -- the immutable record of exactly what the client sent,
--      even if staff later edit the questions. The Edge Function ALSO
--      writes each entry's ranking/notes back onto the matching
--      client_research_questions row (those columns ARE the customer's
--      ranking / customer_notes), so the internal Controlling Document
--      form reflects the client's input; the response row is the audit
--      trail.
--   2. notify_controlling_doc_finalized() trigger -- same shape as 078's
--      notify_evaluation_submitted(): fires an in-app bell notification
--      (Super Admin only, like every notification in this app) the instant
--      a response lands. No email here on purpose -- the bell is the
--      reliable channel (see 078's header).
--   3. client_content.controlling_doc_link_url -- the deterministic public
--      link, saved so client_workflow_files.html's "Create Email" button
--      has a stable URL to hand out (mirrors evaluation_link_url from 077).
--      The page fetches everything live from ?client=<id>, so the URL
--      never goes stale when questions change.
--
-- get_client_public_view() / finalize_client() are intentionally NOT
-- touched -- nothing on the client-facing dashboard surfaces a
-- "controlling doc finalized" state, unlike the Close-Out Evaluation.
--
-- Safe to re-run.

-- ---------- 1. deterministic public link column ----------
alter table client_content add column if not exists controlling_doc_link_url text;

-- ---------- 2. client_controlling_doc_responses ----------
create table if not exists client_controlling_doc_responses (
  id                 uuid primary key default gen_random_uuid(),
  client_id          uuid not null references clients(id) on delete cascade,
  submitted_at       timestamptz not null default now(),
  respondent_name    text,
  respondent_email   text,
  overall_notes      text,
  question_responses jsonb not null default '[]'::jsonb  -- [{question_id, question, ranking, notes}]
);

create index if not exists idx_controlling_doc_responses_client
  on client_controlling_doc_responses(client_id);

alter table client_controlling_doc_responses enable row level security;

-- Staff read a client's submitted response the same way they read anything
-- else about that client. No insert/update/delete policy for anon /
-- authenticated on purpose -- the public Edge Function is the only writer,
-- using the service-role client (bypasses RLS), same as
-- client_evaluation_responses (078).
drop policy if exists "controlling doc responses read" on client_controlling_doc_responses;
create policy "controlling doc responses read" on client_controlling_doc_responses for select
using (is_super_admin() or is_assigned_to_client(client_id));

-- ---------- 3. notification trigger ----------
create or replace function notify_controlling_doc_finalized()
returns trigger
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
  v_client_name text;
begin
  select name into v_client_name from clients where id = NEW.client_id;
  insert into notifications (type, client_id, message)
  values (
    'controlling_doc_finalized',
    NEW.client_id,
    coalesce(v_client_name, 'A client') || '''s Controlling Document was finalized by the client -- ready to review.'
  );
  return NEW;
end;
$$;

drop trigger if exists trg_notify_controlling_doc_finalized on client_controlling_doc_responses;
create trigger trg_notify_controlling_doc_finalized
after insert on client_controlling_doc_responses
for each row execute function notify_controlling_doc_finalized();

-- ---------- 4. public form-data RPC ----------
-- No session/login -- a client clicking the link has neither -- so it's
-- security definer + row_security off + granted to anon, same no-session
-- pattern as get_evaluation_form_data() (079).
create or replace function get_controlling_doc_form_data(p_client_id uuid)
returns table (
  client_name  text,
  sponsor_name text,
  questions    jsonb
)
language plpgsql
security definer
set search_path = public
as $$
begin
  set local row_security = off;

  return query
    select
      c.name,
      (select edc.name from econ_dev_companies edc where edc.id = c.econ_dev_company_id),
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id', q.id,
            'research_area', q.research_area,
            'question', q.question,
            'background', q.background,
            'ranking', q.ranking,
            'customer_notes', q.customer_notes,
            'sort_order', q.sort_order
          )
          order by q.research_area, q.sort_order
        )
        from client_research_questions q
        where q.client_id = c.id
          and coalesce(nullif(trim(q.question), ''), '') <> ''
      ), '[]'::jsonb)
    from clients c
    where c.id = p_client_id;
end;
$$;

grant usage on schema public to anon;
grant execute on function get_controlling_doc_form_data(uuid) to anon;
