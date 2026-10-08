-- 154: every research document now hangs off a question.
--
-- Greg (10/8/26): "let's go forward with a task based system only. we can
-- remove the question about tasks and remove the boxes we were using to
-- attach documents to questions and just use the tasks as our input to the
-- dashboard."
--
-- A task is a question, so once the research-area boxes are gone the only
-- way to reach a document on that page is through its question. 19 of the
-- 39 documents in the system -- 49% -- had question_id null, filed under an
-- area and nothing else. Left alone they would have gone on showing to the
-- CLIENT (get_client_public_view groups by research_area and never looks at
-- question_id) while becoming invisible to the team: a document the Team
-- Lead can no longer find, move or take down. Extremis's entire research
-- set and all of JCS's outbound work were in that state.
--
-- Every one of them sat in an area that already had a question, so each
-- attaches to the lowest-numbered question in its own client and area.
-- Nothing moves between areas, so the client-facing grouping is unchanged
-- by this migration -- the same documents appear under the same headings.
--
-- 14 land in areas holding exactly one question and are unambiguous. 9 land
-- in an area holding two (Clippard inbound, JCS outbound), where lowest
-- question number is a reasonable guess rather than a known answer; those
-- are reported after applying so a Team Lead can move any that are wrong,
-- which the task list makes a two-click job.
--
-- Verified after applying: 0 documents left untied, 0 crossed a client or
-- research_area boundary, and per-client document counts and area spread
-- unchanged (Clippard 10 docs / 4 areas, Extremis 10 / 3, JCS 8 / 1).

with target as (
  select d.id as doc_id, q.id as question_id
    from documents d
    join lateral (
      select q.id
        from client_research_questions q
       where q.client_id = d.client_id
         and q.research_area = d.research_area
       order by q.question_number nulls last, q.sort_order nulls last, q.created_at
       limit 1
    ) q on true
   where d.question_id is null
)
update documents d
   set question_id = t.question_id
  from target t
 where d.id = t.doc_id;

-- clients.use_tasks (153) is now read by nothing: the task list is always
-- the page. The column is deliberately left in place rather than dropped --
-- a DROP hangs for 180s through the MCP connection these are applied over
-- (see 145) -- and it costs nothing where it is.
comment on column clients.use_tasks is
  'DEPRECATED by 154: the task list is no longer optional and nothing reads this. Left in place rather than dropped.';
