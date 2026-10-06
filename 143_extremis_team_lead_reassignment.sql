-- 143_extremis_team_lead_reassignment.sql   (10/6/26)
--
-- Greg, hitting "Couldn't save that -- only this engagement's Team Lead or an
-- Admin can change what its dashboard shows" on Extremis Systems, on a page
-- that said "Team Lead: Greg Gotcher", while signed in as Greg Gotcher.
--
-- Not a bug. There are three Roster entries named Greg Gotcher:
--   greg.gotcher@leadforcesolutions.com  team_lead   led Clippard, EG Training, JCS
--   greg@leadforcesolutions.com          super_admin led Extremis Systems
--   greggotcher@gmail.com                consultant  leads nothing
-- On Extremis he was assigned as the Digital Marketing specialist, so
-- is_team_lead_of_client() was correctly false. Extremis was the only
-- engagement led by the admin account; the other three were already under
-- greg.gotcher@. Greg chose to move it rather than switch accounts per
-- engagement.
--
-- This is a data repair, recorded here because it was applied by hand through
-- the MCP connection rather than through the app's own Assign TL control.
-- The specialty_type='team_lead' row moves to the account he actually works
-- in; his digital_marketing row on the same engagement is left alone.
--
-- enforce_team_lead_assignment() gates on is_super_admin(), which reads
-- auth.uid(), so the statement ran with request.jwt.claims set to his own
-- super-admin account. The trigger itself was never disabled.
--
-- Already applied. Safe to re-run: it matches nothing once the row has moved.
do $$
declare n int;
begin
  perform set_config('request.jwt.claims',
    '{"sub":"1236c809-f3a3-4189-a767-7ad5d31e8314","role":"authenticated"}', true);

  update client_assignments ca
     set user_id = '023f54b5-6cdf-4742-bd3a-c230c5207222'   -- greg.gotcher@
    from clients c
   where c.id = ca.client_id
     and c.name = 'Extremis Systems'
     and ca.is_team_lead
     and ca.user_id = '1236c809-f3a3-4189-a767-7ad5d31e8314'; -- greg@

  get diagnostics n = row_count;
  raise notice 'team-lead rows moved: %', n;
end $$;
