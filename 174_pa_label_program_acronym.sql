-- 174_pa_label_program_acronym.sql
--
-- Greg (10/20/26): "use the program acronym and the title Program
-- Administrator."
--
-- 173 labelled the Program Administrator with their own job title where
-- they had one, which made the same role read differently on every
-- dashboard -- Katie Bresnan as "Business Development Manager", Jon Mardis
-- as "Program Manager", Kenny Sadler, who has no title on file, as "Program
-- Administrator". The client has no way to tell those are one role. The
-- label is now the Program's code plus the role: "GRE Program
-- Administrator", "ALLOY Program Administrator", "AdVal Program
-- Administrator".
--
-- Second half of this: a Program Administrator now always renders through
-- the PA branch. Clippard and JCS had picked theirs onto the team by hand
-- (client_partner_contacts.on_client_team), so they came through the picked
-- branch on their own job title and the PA branch skipped them to avoid a
-- duplicate. Excluding PAs from the picked branch and dropping that skip
-- gives one label for the role everywhere; other picked contacts keep their
-- own titles, which is right -- they are there as themselves.

do $$
declare
  v_def text := pg_get_functiondef('public.get_client_public_view(text)'::regprocedure);
  v_new text;
  v_old constant text :=
    'coalesce(nullif(btrim(pa.title), ''''), ''Program Administrator'')';
  v_lbl constant text :=
    'btrim(coalesce((select edc2.code from econ_dev_companies edc2 where edc2.id = v_client.econ_dev_company_id), '''') || '' Program Administrator'')';
begin
  if position(v_old in v_def) = 0 then raise exception 'PA label not found'; end if;
  v_def := replace(v_def, v_old, v_lbl);

  v_new := replace(v_def,
    '          where ctpc.client_id = v_client.id and pc.active',
    '          where ctpc.client_id = v_client.id and pc.active and not pc.is_program_administrator');
  if v_new = v_def then raise exception 'picked-contacts filter not found'; end if;

  v_def := v_new;
  v_new := replace(v_def,
    '            and not exists (' || chr(10) ||
    '              select 1 from client_partner_contacts cpc2' || chr(10) ||
    '               where cpc2.client_id = v_client.id' || chr(10) ||
    '                 and cpc2.partner_contact_id = pa.id' || chr(10) ||
    '                 and cpc2.on_client_team' || chr(10) ||
    '            )' || chr(10),
    '');
  if v_new = v_def then raise exception 'PA de-dupe clause not found'; end if;

  execute v_new;
end $$;
