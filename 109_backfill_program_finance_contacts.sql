-- 109_backfill_program_finance_contacts.sql
--
-- One-time data cleanup, not a schema change. The old "EG Programs Contact
-- Info" CSV import couldn't parse free text into structured fields, so any
-- Program Finance contact it created without a pre-existing structured row
-- landed as a placeholder named "Imported from Program Finance" with the
-- real text dumped into Notes (see the CSV import comment in
-- econ_dev_partners_admin.html). That made the new Programs list's Billing
-- column show the placeholder name instead of the actual person -- Greg
-- caught this on Annapolis (9/4/26).
--
-- This splits each of the 19 "Imported from Program Finance" rows'
-- freeform Notes text into Name / Title / Address / Email / Phone by hand
-- (the text is too inconsistent for a safe regex). Genuinely extra
-- information that isn't the primary contact (a CC, a "do not cc"
-- instruction) is kept in Notes rather than discarded. Two rows named a
-- second real contact ("Additional contact listed: ...") -- those become
-- their own Program Finance contact rows instead of staying buried in
-- text. The two Sacramento, CA rows are one contact (dept name + address,
-- no person given) that got split into two placeholder rows -- merged into
-- one, the duplicate deleted.
--
-- Safe to re-run: every statement targets a specific existing id (or, for
-- the two inserts, is idempotent in practice since this file only runs
-- once against this known data snapshot).

-- Annapolis
update econ_dev_partner_contacts set
  name = 'Maria Brown', title = null, address = null,
  email = 'mrb@annapolis.gov', phone = null,
  notes = 'CC: Stephen Rice (smrice@annapolis.gov)'
where id = '9a150b0d-703d-46c6-a344-4637a8061d03';

-- Economic Development Partnership of North Carolina
update econ_dev_partner_contacts set
  name = 'Joyce Spivey', title = 'MEP Manager', address = null,
  email = 'joyce.spivey@edpnc.com', phone = '919.447.7785', notes = null
where id = '8d49316d-16c7-4cc4-b004-bfed31bb6e2e';

-- Empower Rural Iowa -- primary contact, plus a second real contact named
-- in the notes ("Additional Program Finance contact: Sacha Wise...").
update econ_dev_partner_contacts set
  name = 'Robin Bostrom', title = null,
  address = 'Iowa Economic Development Authority, 1963 Bell Avenue, Suite 200, Des Moines, Iowa',
  email = 'Robin.bostrom@iowaeda.com', phone = '545.348.6176', notes = null
where id = '8fb9db44-9bdd-43c8-b754-98fab2257f23';

insert into econ_dev_partner_contacts (organization_id, partner_id, category, name, title, address, email, phone, sort_order)
select organization_id, id, 'program_finance', 'Sacha Wise', 'AmeriCorps Program Manager',
  'Iowa Economic Development Authority, 1963 Bell Avenue, Suite 200, Des Moines, Iowa',
  'Sacha.wise@IowaEDA.com', '545.348.6176', 1
from econ_dev_companies where id = '8fb9db44-9bdd-43c8-b754-98fab2257f23';

-- Grow Ketchikan
update econ_dev_partner_contacts set
  name = 'Deborah Hayden', title = 'Executive Director',
  address = '11011 Victorson Ct, Ketchikan, AK 99901',
  email = 'dh@swiftventure.com', phone = '907.254.5300', notes = null
where id = '1260f838-7178-44a2-afef-cc3a72329252';

-- Henrico County VA -- primary contact, plus a second real contact named
-- in the notes ("Additional contact listed: Lane Bains...").
update econ_dev_partner_contacts set
  name = 'Ashley Kubat', title = 'Director of Administration',
  address = '4300 East Parham Road, Henrico, Virginia 23228',
  email = 'Ashley@henrico.com', phone = 'Direct: 804-501-7523 | Mobile: 804-339-5497', notes = null
where id = 'ae8cbbf7-4928-438c-a1fb-f3293d9aa522';

insert into econ_dev_partner_contacts (organization_id, partner_id, category, name, email, sort_order)
select organization_id, id, 'program_finance', 'Lane Bains', 'Lane@henrico.com', 1
from econ_dev_companies where id = 'ae8cbbf7-4928-438c-a1fb-f3293d9aa522';

-- Kansas City - Blue River Valley
update econ_dev_partner_contacts set
  name = 'Brian Weinberg', title = 'Director, Foundation for Regeneration', address = null,
  email = 'brian@regeneration.us', phone = '817.228.8011',
  notes = 'Do not cc Marc Pollick'
where id = 'a3899c85-9f11-430e-be11-d695a908c2d4';

-- Lucas County, OH
update econ_dev_partner_contacts set
  name = 'Gina Kaczala', title = null,
  address = 'Lucas County Economic Development Corp., 1 Government Center, Suite 800, Toledo, Ohio 43604',
  email = 'gkaczala@co.lucas.oh.us', phone = '419.213.3710', notes = null
where id = 'da7c62e9-08e4-4515-9025-02d26656b9c6';

-- Network Kansas
update econ_dev_partner_contacts set
  name = 'Kristi Pedersen', title = 'Dir Budget',
  address = 'POB 877, Andover, KS 67002',
  email = 'kpedersen@networkKansas.com', phone = '316.425.8808',
  notes = 'CC: Steve Radley; CC: Tiffany Nixon'
where id = '17607678-e788-427b-a721-a417e5423f18';

-- North Carolina State University
update econ_dev_partner_contacts set
  name = 'Madelene Brooks', title = null,
  address = 'NCSU / EIS Purchasing, Campus Box 7902, Raleigh, NC 27695',
  email = 'mmbrooks@ncsu.edu', phone = '910.262.6470', notes = null
where id = 'e47f96a4-aafb-4612-b775-31b69a7903ae';

-- Opportunity Squared (Area 15 Iowa)
update econ_dev_partner_contacts set
  name = 'Carla Eysink', title = 'Executive Director',
  address = 'Marion County Development, 214 E Main St, Knoxville, IA 50138',
  email = 'ceysink@marioncountyiowa.gov', phone = '641.828.2257', notes = null
where id = '202a90cc-2d3e-4a12-9e45-eb4786af53ba';

-- Penn-Northwest Development Corporation
update econ_dev_partner_contacts set
  name = 'Jake Rickert', title = 'Associate Executive Director',
  address = '3580 Innovation Way, Hermitage, PA 16148',
  email = 'Jake@penn-northwest.com', phone = '719-354-3616', notes = null
where id = '3fb7d036-25ce-49fd-966c-288669b1be28';

-- Rancho Cordova
update econ_dev_partner_contacts set
  name = 'Diann Rogers', title = 'President',
  address = 'Rancho Cordova Area Chamber of Commerce, 2729 Prospect Park Drive #107, Rancho Cordova, CA 95670',
  email = 'dhrogers@ranchocordova.org', phone = '916.273.5706', notes = null
where id = 'a8132dfe-cab6-43a8-b179-dd24cfa07fc8';

-- Sacramento, CA -- the two placeholder rows are one contact (department
-- name + address, no person given) split apart. Merge into one, delete
-- the duplicate.
update econ_dev_partner_contacts set
  name = 'Office of Innovation and Econ Dev', title = null,
  address = '915 I Street, New City Hall, Sacramento, CA 95814',
  email = null, phone = null, notes = null
where id = 'b7265a70-bb09-404b-a877-117ce310ad2b';

delete from econ_dev_partner_contacts where id = '6150b9ce-e4cc-40a6-8bb8-06d18ef05d97';

-- Summit Economic Partnership
update econ_dev_partner_contacts set
  name = 'Thayer Hirsh', title = 'ED Director',
  address = 'P.O. Box 1561, Frisco, CO 80443',
  email = 'thayer@summitpartnership.org', phone = '970.343.4607', notes = null
where id = '46aadb30-7f27-4d9d-bc1a-def842f82225';

-- Sussex County, Delaware
-- (phone kept exactly as given in the source doc -- looks like it may be
-- missing a trailing digit, but nothing to safely guess it from.)
update econ_dev_partner_contacts set
  name = 'William Pfaff', title = null,
  address = 'Sussex County Government, 2 The Circle, POB 509, Georgetown, DE 19947',
  email = 'William.pfaff@sussexcountyde.gov', phone = '302.855.770', notes = null
where id = 'abb58df9-9ac5-4319-9bd9-17e9af161d99';

-- Utah State University Eastern
update econ_dev_partner_contacts set
  name = 'Ethan Migliori', title = 'Director Non-credit',
  address = 'Utah State Univ Eastern, 451 E 4009 N, Price, UT 84501',
  email = 'Ethan.migliori@usu.edu', phone = '435.613.5435', notes = null
where id = '07f75809-fc61-415d-8d51-f73d1c8a3f77';

-- Virginia Economic Development Partnership
update econ_dev_partner_contacts set
  name = 'Shirley Dodson', title = 'Business Manager',
  address = '901 East Cary Street #900, Richmond, VA 23219',
  email = 'sdodson@vedp.org', phone = 'Office: 804.545.5719 | Cell: 804.584.9239', notes = null
where id = '1069c274-81e2-4a28-aa41-8970bc8d8ef8';

-- Whiteside County, IL
update econ_dev_partner_contacts set
  name = 'Gary Camarano', title = 'ED Dir',
  address = 'Whiteside County ED, 200 East Knox Street, Morrison, IL 61270',
  email = 'gcamarano@whiteside.org', phone = '815.772.5182', notes = null
where id = '109d764a-a37a-4a17-83b9-f81b2c4f385c';
