-- 144_consolidate_greg_accounts.sql (10/6/26)   [APPLIED]
--
-- Greg: "i don't want to have 3 logins but since i have to test for Admin, TL
-- and Specialist i've created 3 logins. That needs to change. i need to have
-- one login - Admin."
--
-- Survivor: greg.gotcher@leadforcesolutions.com (023f54b5). It already held
-- the things tied to being a person who does work -- 8 assignments, 11 time
-- entries, 5 specialties -- and is Team Lead on all four engagements after
-- 143. Promoted to super_admin; greg@'s authored history moves onto it so old
-- documents, invoices and applications stop being attributed to a second
-- "Greg Gotcher". Re-runnable: every statement is keyed on the old id.
do $$
declare
  old_admin uuid := '1236c809-f3a3-4189-a767-7ad5d31e8314'; -- greg@
  old_spec  uuid := '9461b80f-8693-4594-92da-f0e20c08f919'; -- greggotcher@gmail
  keep      uuid := '023f54b5-6cdf-4742-bd3a-c230c5207222'; -- greg.gotcher@
  n int;
begin
  perform set_config('request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', old_admin), true);

  update users set role = 'super_admin' where id = keep and role <> 'super_admin';

  update documents            set uploaded_by  = keep where uploaded_by  = old_admin;
  update clients              set created_by   = keep where created_by   = old_admin;
  update client_next_steps    set assigned_to  = keep where assigned_to  = old_admin;
  update client_delay_notes   set author_id    = keep where author_id    = old_admin;
  update program_invoices     set created_by   = keep where created_by   = old_admin;
  update audit_log            set user_id      = keep where user_id      = old_admin;
  update client_applications  set submitted_by = keep where submitted_by = old_admin;
  update client_applications  set reviewed_by  = keep where reviewed_by  = old_admin;
  update client_applications  set approved_by  = keep where approved_by  = old_admin;
  update client_application_drafts set created_by = keep where created_by = old_admin;

  -- UNIQUE (notification_id, user_id): no overlap in practice, guarded anyway.
  update notification_recipients nr set user_id = keep
   where nr.user_id = old_admin
     and not exists (select 1 from notification_recipients x
                      where x.user_id = keep and x.notification_id = nr.notification_id);

  -- UNIQUE (user_id, specialty): greg@'s single specialty is 'team_lead',
  -- which the survivor already has. That row cannot move, so it stays on the
  -- archived account where it is inert rather than being deleted.
  update user_specialties us set user_id = keep
   where us.user_id = old_admin
     and not exists (select 1 from user_specialties x
                      where x.user_id = keep and x.specialty = us.specialty);

  update users set archived_at = now(), archived_by = keep, hidden_from_roster = true
   where id in (old_admin, old_spec) and archived_at is null;

  select count(*) into n from client_assignments where user_id = old_admin;
  if n > 0 then raise exception 'old admin still has % assignment rows', n; end if;
end $$;
