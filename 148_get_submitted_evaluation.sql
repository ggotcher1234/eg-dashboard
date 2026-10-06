-- 148_get_submitted_evaluation.sql (10/6/26)   [APPLIED]
--
-- Greg, opening Clippard's Evaluation Sheet on their dashboard: "it is not
-- what i want. i want the real form filled out with the information that was
-- in their pdf."
--
-- The step opened a summary modal -- their ratings as a bulleted list. What
-- belongs behind it is the sheet they actually filled in, in the real layout.
-- evaluation_public.html builds every control from its `state` object, so it
-- only needed the submitted answers handed back to it.
--
-- Capability model matches get_evaluation_form_data: holding the client id IS
-- the capability, because that id is the evaluation link. The table's own
-- SELECT policy (is_super_admin or is_assigned_to_client) gives anon nothing,
-- so this is security definer and returns exactly the fields the sheet
-- renders -- no ids, no internal columns.
--
-- Side benefit: until now a client who reopened their link after submitting
-- got a BLANK form with a live Submit button, so a second response could be
-- filed over the first. The page now shows them their completed sheet.
create or replace function get_submitted_evaluation(p_client_id uuid)
returns table (
  submitted_at            timestamptz,
  respondent_name         text,
  respondent_date         date,
  company_name            text,
  sponsor_name            text,
  question_ratings        jsonb,
  q1_explain              text,
  prepared                text,
  prepared_explain        text,
  improvement_suggestions text,
  nps_score               integer,
  nps_explain             text,
  referrals               jsonb,
  testimonial             text
)
language sql stable security definer set search_path = public as $$
  select r.submitted_at, r.respondent_name, r.respondent_date, r.company_name,
         r.sponsor_name, r.question_ratings, r.q1_explain, r.prepared,
         r.prepared_explain, r.improvement_suggestions, r.nps_score,
         r.nps_explain, r.referrals, r.testimonial
    from client_evaluation_responses r
   where r.client_id = p_client_id
   order by r.submitted_at desc
   limit 1;
$$;

grant execute on function get_submitted_evaluation(uuid) to anon, authenticated;
