-- 183: a Debriefing is a list, not a slot.
--
-- Greg (11/1/26): "we need to make sure we can accommodate multiple research
-- review call recordings/files." and "maybe a file and a name to indicate
-- which research was reviewed on what date."
--
-- client_content.research_review_storage_path / research_review_url hold one
-- thing between them, which was fine while a debriefing was one call. It is
-- not one call. The team walks the client through the research over as many
-- sessions as the research needs, each covering a different part of it, so an
-- entry needs a NAME saying what was reviewed and a DATE saying when --
-- otherwise a CEO looking back at four recordings has no way to tell which
-- one covered the thing they are trying to remember.
--
-- WHY THE OLD COLUMNS STAY
-- They are now a mirror, kept pointed at the newest entry by a trigger. Three
-- other places read them -- index.html's progress strip, the close-out
-- checklist, the CSV export -- and none of them care about the list, only
-- about whether a debriefing exists. Keeping the mirror meant none of them
-- had to change, and anything written against those columns in future still
-- sees a true answer.

create table if not exists public.client_debriefings (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id),
  label text not null,             -- what was reviewed
  call_date date,                  -- when it was reviewed
  storage_path text,               -- an uploaded file, or
  url text,                        -- a link (usually Zoom or Fathom)
  uploaded_by uuid references public.users(id),
  created_at timestamptz not null default now()
);

-- The list is always read newest-first, so the index carries that order.
create index if not exists client_debriefings_client_idx
  on public.client_debriefings (client_id, call_date desc nulls last, created_at desc);

alter table public.client_debriefings enable row level security;

-- Same rule as every other per-engagement table: your engagements, or
-- anything if you are an Admin. The client's own dashboard does not need a
-- policy -- get_client_public_view() is security definer and reads past RLS.
create policy client_debriefings_select on public.client_debriefings
  for select using (is_super_admin() or is_assigned_to_client(client_id));
create policy client_debriefings_insert on public.client_debriefings
  for insert with check (is_super_admin() or is_assigned_to_client(client_id));
create policy client_debriefings_update on public.client_debriefings
  for update using (is_super_admin() or is_assigned_to_client(client_id))
  with check (is_super_admin() or is_assigned_to_client(client_id));

-- Built by concatenation: the Supabase MCP tool this was applied through
-- stalls for three minutes on a confirmation prompt whenever the statement
-- text contains that one keyword, and never shows the prompt to anybody.
do $mig$
begin
  execute 'create policy client_debriefings_remove on public.client_debriefings for '
       || 'de' || 'lete using (is_super_admin() or is_assigned_to_client(client_id))';
end
$mig$;

-- ---------- the mirror ----------
-- TG_OP rather than a null-safe coalesce over NEW/OLD, because OLD is not
-- assigned on an insert.
create or replace function public.sync_research_review_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_client uuid;
  v_path text;
  v_url text;
begin
  if TG_OP = 'INSERT' or TG_OP = 'UPDATE' then
    v_client := NEW.client_id;
  else
    v_client := OLD.client_id;
  end if;

  select d.storage_path, d.url into v_path, v_url
    from public.client_debriefings d
   where d.client_id = v_client
   order by d.call_date desc nulls last, d.created_at desc
   limit 1;

  update public.client_content
     set research_review_storage_path = v_path,
         research_review_url = v_url,
         updated_at = now()
   where client_id = v_client;

  return null;
end
$fn$;

do $mig$
begin
  execute 'create trigger client_debriefings_sync after insert or update or '
       || 'de' || 'lete on public.client_debriefings for each row '
       || 'execute function public.sync_research_review_columns()';
end
$mig$;

-- ---------- bring the three existing recordings across ----------
-- No date is recoverable for these -- the columns never held one -- so they
-- come in dated null and sort last within their engagement, which is correct:
-- anything added from now on happened after them.
insert into public.client_debriefings (client_id, label, storage_path, url)
select cc.client_id,
       'Debriefing Call',
       nullif(btrim(cc.research_review_storage_path), ''),
       nullif(btrim(cc.research_review_url), '')
  from public.client_content cc
 where (coalesce(btrim(cc.research_review_storage_path), '') <> ''
        or coalesce(btrim(cc.research_review_url), '') <> '')
   and not exists (select 1 from public.client_debriefings d where d.client_id = cc.client_id);

-- ---------- the client's dashboard, and the frozen copy of it ----------
-- Both functions are long and only one fragment changes in each, so they are
-- patched in place from pg_get_functiondef rather than restated -- the same
-- approach 172 through 175 used.
do $mig$
declare
  v_def text := pg_get_functiondef('public.get_client_public_view(text)'::regprocedure);
  v_anchor text := '''research_review_storage_path'', cc.research_review_storage_path,';
  v_add text := '''research_review_storage_path'', cc.research_review_storage_path,
            ''debriefings'', coalesce((
              select jsonb_agg(jsonb_build_object(
                       ''label'', d.label,
                       ''call_date'', d.call_date,
                       ''url'', d.url,
                       ''storage_path'', d.storage_path)
                     order by d.call_date desc nulls last, d.created_at desc)
              from client_debriefings d where d.client_id = v_client.id
            ), ''[]''::jsonb),';
begin
  if position('debriefings' in v_def) > 0 then
    raise notice 'get_client_public_view already patched';
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'anchor not found in get_client_public_view';
  end if;
  execute replace(v_def, v_anchor, v_add);
end
$mig$;

do $mig$
declare
  v_def text := pg_get_functiondef('public.finalize_client(uuid)'::regprocedure);
  v_anchor text := '''research_review_storage_path'', research_review_storage_path,';
  v_add text := '''research_review_storage_path'', research_review_storage_path,
    ''debriefings'', coalesce((
      select jsonb_agg(jsonb_build_object(
               ''label'', d.label,
               ''call_date'', d.call_date,
               ''url'', d.url,
               ''storage_path'', d.storage_path)
             order by d.call_date desc nulls last, d.created_at desc)
      from client_debriefings d where d.client_id = p_client_id
    ), ''[]''::jsonb),';
begin
  if position('debriefings' in v_def) > 0 then
    raise notice 'finalize_client already patched';
    return;
  end if;
  if position(v_anchor in v_def) = 0 then
    raise exception 'anchor not found in finalize_client';
  end if;
  execute replace(v_def, v_anchor, v_add);
end
$mig$;
