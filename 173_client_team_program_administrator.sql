-- 173_client_team_program_administrator.sql
--
-- Greg (10/20/26): "let's also add the Program PA to the NCEG team list."
--
-- Read off the Program rather than off the engagement. An engagement can
-- pick Program contacts onto its team by hand (client_partner_contacts
-- .on_client_team) and some have -- Clippard picked Jon Mardis, JCS picked
-- Katie Bresnan -- but most have not, and the Program Administrator is a
-- property of the Program, not a per-engagement decision. So it comes from
-- econ_dev_partner_contacts.is_program_administrator for the engagement's
-- Program, and an engagement that already picked them is skipped so nobody
-- is listed twice.
--
-- Order, after 172 set it: Team Lead, specialists, any Program contacts the
-- engagement picked, the Program Administrator, then the standing roster
-- names (Chris). Admin and QC stay filtered client-side.
--
-- Label: their own title where they have one, "Program Administrator" where
-- they do not. Katie Bresnan reads "Business Development Manager", Kenny
-- Sadler has no title on file and reads "Program Administrator".
--
-- As in 172, rewritten from the live definition rather than retyped, with
-- each replace checked so a moved definition raises instead of half-applying.

do $$
declare
  v_def text := pg_get_functiondef('public.get_client_public_view(text)'::regprocedure);
  v_new text;
  v_pa  text :=
    '          select jsonb_agg(jsonb_build_object(''name'', pa.name, ''specialty'', coalesce(nullif(btrim(pa.title), ''''), ''Program Administrator''), ''email'', pa.email, ''phone'', pa.phone) order by pa.sort_order, pa.name)' || chr(10) ||
    '          from econ_dev_partner_contacts pa' || chr(10) ||
    '          where pa.partner_id = v_client.econ_dev_company_id' || chr(10) ||
    '            and pa.is_program_administrator' || chr(10) ||
    '            and pa.active' || chr(10);
begin
  -- Live branch: after the engagement team and the Program contacts it
  -- picked, before the standing roster names.
  v_new := replace(v_def,
    '        ), ''[]''::jsonb)' || chr(10) ||
    '        ||' || chr(10) ||
    '        coalesce((' || chr(10) ||
    '          select jsonb_agg(jsonb_build_object(''name'', fu.full_name,',
    '        ), ''[]''::jsonb)' || chr(10) ||
    '        ||' || chr(10) ||
    '        coalesce((' || chr(10) || v_pa ||
    '            and not exists (' || chr(10) ||
    '              select 1 from client_partner_contacts cpc2' || chr(10) ||
    '               where cpc2.client_id = v_client.id' || chr(10) ||
    '                 and cpc2.partner_contact_id = pa.id' || chr(10) ||
    '                 and cpc2.on_client_team' || chr(10) ||
    '            )' || chr(10) ||
    '        ), ''[]''::jsonb)' || chr(10) ||
    '        ||' || chr(10) ||
    '        coalesce((' || chr(10) ||
    '          select jsonb_agg(jsonb_build_object(''name'', fu.full_name,');
  if v_new = v_def then raise exception 'live-branch anchor not found'; end if;

  -- Finalized branch: appended to the frozen snapshot rather than written
  -- into it, and skipped if that address is already there.
  v_def := v_new;
  v_new := replace(v_def,
    '        s.team || coalesce((',
    '        s.team || coalesce((' || chr(10) || v_pa ||
    '            and not exists (' || chr(10) ||
    '              select 1 from jsonb_array_elements(s.team) t2' || chr(10) ||
    '               where lower(t2->>''email'') = lower(pa.email)' || chr(10) ||
    '            )' || chr(10) ||
    '        ), ''[]''::jsonb) || coalesce((');
  if v_new = v_def then raise exception 'finalized-branch anchor not found'; end if;

  execute v_new;
end $$;
