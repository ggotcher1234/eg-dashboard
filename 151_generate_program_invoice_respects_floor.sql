-- 151: generate_program_invoice() consults the floor from 150.
--
-- Patched by rewriting pg_get_functiondef() output rather than retyping the
-- body. 062 defined this function and several migrations have touched it
-- since; retyping it from the repo copy would silently revert whatever of
-- those is not in the file I happen to be looking at. The guard below makes
-- the patch fail loudly if the text it expects is not there, instead of
-- installing a function that quietly lost something.
--
-- Net effect, one line of the body:
--     max(seq this year) + 1
-- becomes
--     greatest( max(seq this year) + 1, this year's floor )
--
-- Verified after applying: next_seq for 2026 = 58, with the live maximum
-- still at 8, and the advisory lock / admin guard / setup-fee / sunk-cost
-- blocks all still present (1809 -> 2255 chars).

do $$
declare
  v_def  text;
  v_old  text;
  v_new  text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'generate_program_invoice'
     and p.oid::regprocedure::text =
         'generate_program_invoice(uuid,uuid,text,date,jsonb,numeric,uuid[],uuid[])';

  if v_def is null then
    raise exception '151: generate_program_invoice not found with the expected signature.';
  end if;

  v_old := '  select coalesce(max((split_part(invoice_number, ''-'', 2))::int), 0) + 1' || E'\n' ||
           '  into v_next_seq' || E'\n' ||
           '  from program_invoices' || E'\n' ||
           '  where invoice_number like (v_year || ''-%'');';

  if position(v_old in v_def) = 0 then
    raise exception '151: the sequence block in generate_program_invoice does not look the way 150 expected. Not patching.';
  end if;

  v_new := '  -- Whichever is higher: the next number after the highest issued' || E'\n' ||
           '  -- this year, or the year''s configured starting point (150). The' || E'\n' ||
           '  -- floor keeps working after the test invoices are deleted at' || E'\n' ||
           '  -- go-live, when the live maximum drops back to nothing.' || E'\n' ||
           '  select greatest(' || E'\n' ||
           '           coalesce(max((split_part(invoice_number, ''-'', 2))::int), 0) + 1,' || E'\n' ||
           '           coalesce((select f.first_seq' || E'\n' ||
           '                       from program_invoice_number_floor f' || E'\n' ||
           '                      where f.invoice_year = v_year), 1)' || E'\n' ||
           '         )' || E'\n' ||
           '  into v_next_seq' || E'\n' ||
           '  from program_invoices' || E'\n' ||
           '  where invoice_number like (v_year || ''-%'');';

  execute replace(v_def, v_old, v_new);
end $$;
