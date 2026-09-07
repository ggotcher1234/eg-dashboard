-- 113_import_program_contacts.sql
--
-- Depends on 112_program_contacts_and_address.sql. RUN 112 FIRST -- every
-- column this writes to is created there.
--
-- Greg (9/7/26), handing over Chris's "EG PROGRAMS CONTACT INFO" doc dated
-- 6/25/26: "can you pull all this data into the program page."
--
-- WHAT THIS IS
-- The doc is a 3-column Word table -- Primary Contact / Program Administrator
-- / Program Finance -- with each cell holding free-form blocks of name, title,
-- organisation, address, email and phone, plus sub-lists ("Regional
-- Directors", "Regional Managers", "All communications", "Do not cc:") and
-- Chris's own contract notes ("7/1/19 (10 co) No NDA"). It was parsed into the
-- rows below; the parse is checked into the repo alongside this file so the
-- import can be re-derived rather than re-typed.
--
-- 32 Programs, 101 people. A person listed in more than one column is ONE row
-- with more than one role flag -- Terrell Ellis is Primary Contact, Program
-- Administrator and Program Finance for Advantage Valley, which is exactly the
-- case that made roles flags instead of a category in 112.
--
-- HOW IT MERGES  (Greg chose "match on email, fill gaps")
--   * A Program is found by a distinctive phrase in its name, not by an exact
--     match -- the doc says "SUSSEX COUNTY, DELEWARE" and the dashboard may
--     well say something else. If that phrase matches two Programs the import
--     skips it and says so rather than guessing.
--   * A Program named in the doc with no match in the dashboard is created.
--   * A contact already in the dashboard with the same email keeps everything
--     it has; only empty fields get filled, and role flags are OR-ed in. A
--     contact whose email the doc doesn't have is matched on name instead.
--   * Nothing is ever deleted, and no existing value is overwritten.
--
-- Every step reports what it did with RAISE NOTICE, so the SQL editor's output
-- pane is the import log. Safe to re-run: a second run fills nothing new.

alter table econ_dev_companies add column if not exists notes text;
comment on column econ_dev_companies.notes is
  'Free-form Program notes -- contract dates, NDA status, anything the
   structured fields have no room for.';

-- Plain temp tables, not ON COMMIT DROP: the Supabase SQL editor runs each
-- statement on its own commit, which would drop them before the next line.
drop table if exists _imp_program;
drop table if exists _imp_contact;

create temporary table _imp_program (
  doc_name text primary key, match_phrase text, code_hint text,
  street text, city text, state text, zip text, phone text, notes text
);

create temporary table _imp_contact (
  doc_name text, seq int, name text, title text, email text, phone text,
  region text, org text, notes text,
  is_primary boolean, is_admin boolean, is_finance boolean,
  is_rd boolean, cc boolean
);

insert into _imp_program values
  ('ADVANTAGE VALLEY (WEST VIRGINIA)', 'ADVANTAGE VALLEY', 'ADVVALLEY', 'P.O. Box 1925', 'Charleston', 'WV', '25327', '304.352.1165', null),
  ('ALLOY DEVELOPMENT', 'ALLOY', 'ALLOY', '1776 Mentor Avenue, Suite 100', 'Cincinnati', 'OH', '45212', '513-458-2230', '7/1/19 (10 co)  No NDA'),
  ('ANNAPOLIS', 'ANNAPOLIS', 'ANNAPOLIS', '145 Gorman Street, 3rd Floor', 'Annapolis', 'MD', '21401', '410-260-2200 ext 7770', null),
  ('CABARRUS COUNTY, NORTH CAROLINA', 'CABARRUS', 'CABARRUS', '3003 Dale Earnhardt Blvd #2', 'Kannapolis', 'NC', '28083', '704.490.4974', null),
  ('ECONOMIC DEVELOPMENT PARTNERSHIP OF NORTH CAROLINA', 'PARTNERSHIP OF NORTH CAROLINA', 'EDPNC', null, null, null, null, '919.447.7739', null),
  ('GREATER OMAHA CHAMBER', 'OMAHA', 'OMAHA', '808 Conagra Drive, Suite 400', 'Omaha', 'NE', '68102', '402-978-7935', null),
  ('GREATER ROCHESTER ENTERPRISE', 'ROCHESTER', 'GRE', '100 Chestnut Street, Ste 1910', 'Rochester', 'NY', '14604', '585.530.6200', '5/30/19 +3  (40 co)  No NDA (doesn’t want)'),
  ('GROW KETCHIKAN', 'KETCHIKAN', 'KETCHIKAN', '11011 Victorson Ct', 'Ketchikan', 'AK', '99901', '907.254.5300', null),
  ('HENRICO COUNTY VA', 'HENRICO', 'HENRICO', '4300 East Parham Road', 'Henrico', 'VA', '23228', '804-501-7523', null),
  ('HONDO, TEXAS', 'HONDO', 'HONDO', null, null, null, null, null, null),
  ('INVEST BUFFALO NIAGARA', 'BUFFALO', 'BUFFALO', '403 Main Street, Suite 624', 'Buffalo', 'NY', '14203', '716-359-0337', null),
  ('KANSAS CITY – Blue River Valley', 'BLUE RIVER', 'BLUERIVER', '5101 Santa Monica Blvd, Ste 8 PMB 137', 'Los Angeles', 'CA', '90020', null, null),
  ('LUCAS COUNTY OH', 'LUCAS', 'LUCAS', 'One Government Center, Suite 800', 'Toledo', 'OH', '43604', '(419) 930-7786', null),
  ('NETWORK KANSAS', 'NETWORK KANSAS', 'NETKANSAS', '550 North 159th Street East', 'Wichita', 'KS', '67230', '877.521.8600', '6/12/19 +3 (5 co)  No NDA'),
  ('NORTH CAROLINA STATE UNIVERSITY', 'NORTH CAROLINA STATE UNIVERSITY', 'NCSU', 'Campus Box 7902', 'Raleigh', 'NC', '27695', '919.515.2358', null),
  ('NORTHWEST HILLS COUNCIL OF GOVERNMENTS', 'NORTHWEST HILLS', 'NWHILLS', null, null, null, null, null, null),
  ('OPPORTUNITY SQUARED (AREA 15 IOWA)', 'OPPORTUNITY SQUARED', 'OPPSQUARED', '224 East Second Street', 'Ottumwa', 'IA', '52501', '641.684.6551', null),
  ('Penn-Northwest Development Corporation', 'PENNNORTHWEST', 'PENNNW', null, null, null, null, null, null),
  ('RANCHO CORDOVA', 'RANCHO CORDOVA', 'RANCHO', '2729 Prospect Park Drive  #107', 'Rancho Cordova', 'CA', '95670', '916.273.5706', null),
  ('REXBURG, IDAHO', 'REXBURG', 'REXBURG', null, null, null, null, null, null),
  ('RICHARDSON, TEXAS', 'RICHARDSON', 'RICHARDSON', '411 Belle Grove Drive', 'Richardson', 'TX', '75080', '972.792.2817', null),
  ('SAHUARITA, ARIZONA', 'SAHUARITA', 'SAHUARITA', '375 West Sahuarita Center Way', 'Sahuarita', 'AZ', '85629', '520.822.8817', null),
  ('SACRAMENTO', 'SACRAMENTO', 'SACRAMENTO', '915 I Street   4th floor', 'Sacramento', 'CA', '95814', '916-541-6408', '10/2/19  (7 co), no NDA'),
  ('SANDOVAL ECONOMIC ALLIANCE (NEW MEXICO)', 'SANDOVAL', 'SANDOVAL', '1201 Rio Rancho Blvd. Suite C', 'Rio Rancho', 'NM', '87124', '505.891.4305', null),
  ('SHENANDOAH VALLEY PARTNERSHIP (VIRGINIA)', 'SHENANDOAH', 'SHENANDOAH', '220 University Blvd, Ste 2100', 'Harrisonburg', 'VA', '22801', '540.568.3259', '5/1/2020 +3 yrs  (5 co)'),
  ('SUMMIT ECONOMIC PARTNERSHIP', 'SUMMIT', 'SUMMIT', null, null, null, null, null, null),
  ('SUSSEX COUNTY, DELEWARE', 'SUSSEX', 'SUSSEX', '2 The Circle, POB 509', 'Georgetown', 'DE', '19947', '302.855.770', '3/12/19  (5 co)  No NDC'),
  ('TRICITY, WASHINGTON', 'TRICITY', 'TRICITY', null, null, null, null, '509.491.3234', '7/6/19  (3 co) No NDA'),
  ('UTAH STATE UNIVERSITY EASTERN', 'UTAH STATE', 'USUE', '451 E 4009 N', 'Price', 'UT', '84501', '435.613.5435', '2/8/19  (5 co)  No NDA'),
  ('VIRGINIA ECONOMIC DEVELOPMENT PARTNERSHIP', 'VIRGINIA ECONOMIC DEVELOPMENT', 'VEDP', '901 East Cary Street  #900', 'Richmond', 'VA', '23219', '804.545.5719', '7/30/19 + 3 (18 co) No NDA'),
  ('WHITESIDE COUNTY, IL', 'WHITESIDE', 'WHITESIDE', '200 East Knox Street', 'Morrison', 'IL', '61270', '815.772.5182', '5/6/19 (5 co)  No NDA'),
  ('YORK, PENNSYLVANIA', 'YORK', 'YORK', '401 Hume Avenue', 'Alexandria', 'VA', '22301', '717.318.4090', 'Jun 4, 2019 (5 co) Yes NDA');

insert into _imp_contact values
  ('ADVANTAGE VALLEY (WEST VIRGINIA)', 0, 'Terrell Ellis', 'Executive Director', 'terrell@advantagevalley.com', '304.352.1165', null, 'Advantage Valley', null, true, true, true, false, true),
  ('ADVANTAGE VALLEY (WEST VIRGINIA)', 1, 'Marjorie Cook', 'Marketing and Communications', 'marjorie@advantagevalley.com', '304.541.9657', null, null, null, false, true, false, false, true),
  ('ADVANTAGE VALLEY (WEST VIRGINIA)', 2, 'Sam Lever', null, 'sam@advantagevalley.com', null, null, null, null, false, true, false, false, true),
  ('ADVANTAGE VALLEY (WEST VIRGINIA)', 3, 'Kris Mitchell', 'Executive Director', 'director@boonecountywv.org', '304.369.9118', 'Boone County Community and Economic Development Authority', 'Boone County Community and Economic Development Authority', null, false, false, false, true, true),
  ('ADVANTAGE VALLEY (WEST VIRGINIA)', 4, 'Dave Lieving', 'President & CEO', 'dlieving@hadco.org', '304.525.1161', 'Huntington Area Development Council + Wayne County', 'Huntington Area Development Council + Wayne County', null, false, false, false, true, true),
  ('ADVANTAGE VALLEY (WEST VIRGINIA)', 5, 'Adam Phillips', 'Business Retention Specialist', 'aphillips@hadco.org', '304.633.0990', 'Huntington Area Development Council', 'Huntington Area Development Council', null, false, false, false, true, true),
  ('ADVANTAGE VALLEY (WEST VIRGINIA)', 6, 'Victoria Russo', 'New Markets Consultant', 'vrusso@charlestonareaalliance.org', '304.340.4253', 'Clay County Business Development Authority', 'Clay County Business Development Authority', null, false, false, false, true, true),
  ('ADVANTAGE VALLEY (WEST VIRGINIA)', 7, 'Nicole Christian', 'President & CEO', 'nchristian@charlestonareaalliance.org', '304.340.4253', 'Charleston Area Alliance', 'Charleston Area Alliance', null, false, false, false, true, true),
  ('ADVANTAGE VALLEY (WEST VIRGINIA)', 8, 'Mark Whitley', 'Executive Director', 'director@jcda.org', '304.372.1151', 'Jackson County Development Authority', 'Jackson County Development Authority', null, false, false, false, true, true),
  ('ADVANTAGE VALLEY (WEST VIRGINIA)', 9, 'Tommy Adkins', 'Executive Director', 'tommy@lincolneda.com', '304.824.3838', 'Lincoln County Economic Development Authority', 'Lincoln County Economic Development Authority', null, false, false, false, true, true),
  ('ADVANTAGE VALLEY (WEST VIRGINIA)', 10, 'John Musgrave', 'Executive Director', 'mcdadir@masoncounty.org', '304.675.1497', 'Mason County Economic Development Authority', 'Mason County Economic Development Authority', null, false, false, false, true, true),
  ('ADVANTAGE VALLEY (WEST VIRGINIA)', 11, 'Morganne Tenney', 'Executive Director', 'mtenney@pcda.org', '304.757.0318', 'Putnam County Development Authority', 'Putnam County Development Authority', null, false, false, false, true, true),
  ('ADVANTAGE VALLEY (WEST VIRGINIA)', 12, 'Dave Lieving', 'Executive Director', 'dlieving@wceda.org', '304.525.1161', 'Wayne County Economic Development Authority', 'Wayne County Economic Development Authority', null, false, false, false, true, true),
  ('ADVANTAGE VALLEY (WEST VIRGINIA)', 13, 'Adam Phillips', 'Business Retention Specialist', 'aphillips@wceda.org', '304.633.0990', 'Business Retention Specialist', null, null, false, false, false, true, true),
  ('ALLOY DEVELOPMENT', 0, 'Harry Blanton', 'Sr. Vice President, Economic Development', 'hblanton@alloydev.org', 'Office: 513-458-2230 / Cell: 513-476-9722', null, null, null, true, false, false, false, false),
  ('ALLOY DEVELOPMENT', 1, 'Jon Mardis', null, 'jmardis@alloydev.org', '513-458-2210', null, null, null, false, true, true, false, false),
  ('ALLOY DEVELOPMENT', 2, 'Bob Pickford', 'Business Coach', 'bpickford@alloydev.org', 'Cell: 513-675-7432', null, null, null, false, true, false, false, false),
  ('ALLOY DEVELOPMENT', 3, 'Greg Forte', 'Director of Small Business Services', 'gforte@alloydev.org', '513-458-2210', null, null, null, false, true, false, false, false),
  ('ANNAPOLIS', 0, 'Stephen Rice', 'Director', 'smrice@annapolis.gov', 'Phone: 410-260-2200 ext 7770 / Mobile: 443-808-5737', null, 'Planning and Zoning, City of Annapolis', null, true, true, false, false, true),
  ('ANNAPOLIS', 1, 'Hope Stewart', null, null, '410-260-2200  x 7787', null, null, null, false, true, false, false, false),
  ('ANNAPOLIS', 2, 'Maria Brown', null, 'mrb@annapolis.gov', null, null, null, null, false, false, true, false, false),
  ('CABARRUS COUNTY, NORTH CAROLINA', 0, 'Brian Hiatt', 'Interim Director', 'pcastrodale@cabarrus.biz', '704.490.4974', null, 'Cabarrus Economic Dev.', null, true, false, true, false, false),
  ('CABARRUS COUNTY, NORTH CAROLINA', 1, 'Stephanie Burleson', 'Business Support Mgr.', 'Sburleson@cabarrusedc.com', '704-440-3763', null, 'Cabarrus Economic Dev.', null, false, true, false, false, false),
  ('ECONOMIC DEVELOPMENT PARTNERSHIP OF NORTH CAROLINA', 0, 'John Loyack', 'VP Global Business Services', 'john.loyack@edpnc.com', '919.447.7739', null, null, null, true, false, false, false, false),
  ('ECONOMIC DEVELOPMENT PARTNERSHIP OF NORTH CAROLINA', 1, 'Harry Swendsen', 'Contract Mgr.', 'harry.swendsen@edpnc.com', '919.703.5369', null, null, null, false, true, false, false, true),
  ('ECONOMIC DEVELOPMENT PARTNERSHIP OF NORTH CAROLINA', 2, 'Bill Slagle', 'Director Statewide and NW Existing Industry Expansion', 'bill.slagle@edpnc.com', '828.592.1029', null, null, null, false, true, false, false, true),
  ('ECONOMIC DEVELOPMENT PARTNERSHIP OF NORTH CAROLINA', 3, 'Chris McGraw', null, 'chris_mcgraw@ncsu.edu', 'Phone: 828-329-3119', null, 'NCSU IES Regional Manager - Western', null, false, true, false, false, true),
  ('ECONOMIC DEVELOPMENT PARTNERSHIP OF NORTH CAROLINA', 4, 'Beth Norman', 'Director of Existing Industry Relations', 'beth@ccedp.com', '941.962.5242', null, null, null, false, true, false, false, true),
  ('ECONOMIC DEVELOPMENT PARTNERSHIP OF NORTH CAROLINA', 5, 'Harry Swendsen', 'North Central', 'harry.swendsen@edpnc.com', '919.703.5369', 'North Central', null, null, false, false, false, true, true),
  ('ECONOMIC DEVELOPMENT PARTNERSHIP OF NORTH CAROLINA', 6, 'James Wolfe', 'Southeast', 'james.wolfe@edpnc.com', '910.620.7981', 'Southeast', null, null, false, false, false, true, true),
  ('ECONOMIC DEVELOPMENT PARTNERSHIP OF NORTH CAROLINA', 7, 'Melanie Underwood', 'Southwest', 'melanie.underwood@edpnc', '980.256.0497', 'Southwest', null, null, false, false, false, true, true),
  ('ECONOMIC DEVELOPMENT PARTNERSHIP OF NORTH CAROLINA', 8, 'Mike Hubbard', 'South Central Sandhills', 'mike.hubbard@edpnc', null, 'South Central Sandhills', null, null, false, false, false, true, true),
  ('ECONOMIC DEVELOPMENT PARTNERSHIP OF NORTH CAROLINA', 9, 'Sarah Bernart', 'Northeast', 'sarah.bernart@edpnc', '252.343.2653', 'Northeast', null, null, false, false, false, true, true),
  ('ECONOMIC DEVELOPMENT PARTNERSHIP OF NORTH CAROLINA', 10, 'Lori Benn', 'Northeast', 'lbenn@ncsu.edu', '919-988-7475', 'Northeast', null, null, false, false, false, true, true),
  ('ECONOMIC DEVELOPMENT PARTNERSHIP OF NORTH CAROLINA', 11, 'Tracy Dellinger', 'Piedmont Triad', 'tracy.dellinger@edpnc.com', '336.214.7283', 'Piedmont Triad', null, null, false, false, false, true, true),
  ('ECONOMIC DEVELOPMENT PARTNERSHIP OF NORTH CAROLINA', 12, 'April Riddle', 'Western Region', 'april.riddle@edpnc.com', '828.772.9128', 'Western Region', null, null, false, false, false, true, true),
  ('ECONOMIC DEVELOPMENT PARTNERSHIP OF NORTH CAROLINA', 13, 'Jennifer Holcomb', 'Sandhills', 'Jennifer.holcomb@edpnc.com', '910.640.8287', 'Sandhills', null, null, false, false, false, true, true),
  ('ECONOMIC DEVELOPMENT PARTNERSHIP OF NORTH CAROLINA', 14, 'Mitch Poteat', null, 'jmpoteat@ncsu.edu', '919-607-0684', 'Regional Manager, NC State University Industry Expansion Solutions (IES)', 'Regional Manager, NC State University Industry Expansion Solutions (IES)', null, false, false, false, true, true),
  ('ECONOMIC DEVELOPMENT PARTNERSHIP OF NORTH CAROLINA', 15, 'Joyce Spivey', 'MEP Manager', 'joyce.spivey@edpnc.com', '919.447.7785', null, null, null, false, false, true, false, false),
  ('GREATER OMAHA CHAMBER', 0, 'Alec Gorynski', 'SVP of Economic Development', 'agorynski@selectgreateromaha.co', '402-978-7935', null, null, null, true, false, false, false, false),
  ('GREATER OMAHA CHAMBER', 1, 'Makayla Leiting', 'Business Attraction Retention', 'mleiting@selectgreateromaha.com', 'Office: 402-233-7150', null, null, null, false, true, true, false, false),
  ('GREATER ROCHESTER ENTERPRISE', 0, 'Matt Hurlbutt', 'President', 'matt@rochesterbiz.com', '585.530.6200', null, 'Greater Rochester Enterprise', null, true, false, false, false, true),
  ('GREATER ROCHESTER ENTERPRISE', 1, 'Katie Bresnan', 'Business Dev. Mgr', 'KatieB@rochesterbiz.com', '585.530.6217 / 585.733.7225', null, 'Greater Rochester Enterprise', null, false, true, false, false, false),
  ('GREATER ROCHESTER ENTERPRISE', 2, 'Ray Zayas', 'Business Dev. Mgr.', 'Raymond@rochesterbiz.com', null, null, null, null, false, true, false, false, false),
  ('GREATER ROCHESTER ENTERPRISE', 3, 'Jared Jones', null, 'jared@rochesterbiz.com', null, null, null, null, false, true, false, false, false),
  ('GREATER ROCHESTER ENTERPRISE', 4, 'David Grome', null, 'david@rochesterbiz.com', null, null, null, null, false, true, false, false, false),
  ('GREATER ROCHESTER ENTERPRISE', 5, 'Theresa Cline', null, 'Theresa@rochesterbiz.com', null, null, null, null, false, true, false, false, false),
  ('GREATER ROCHESTER ENTERPRISE', 6, 'Staci Henning', 'VP Mktg', 'staci@rochesterbiz.com', '585.530.6211', null, 'Greater Rochester Enterprise', null, false, false, true, false, false),
  ('GREATER ROCHESTER ENTERPRISE', 7, 'Faye Pelow', 'Mgr Support Ops', 'faye@rochesterbiz.com', '585.530.6204', null, 'Greater Rochester Enterprise', null, false, false, true, false, false),
  ('GROW KETCHIKAN', 0, 'Deborah Hayden', 'Executive Director', 'dh@swiftventure.com', '907.254.5300', null, null, 'Grow Ketchikan', true, true, true, false, false),
  ('HENRICO COUNTY VA', 0, 'Andrew Larsen', null, 'Andrew@henrico.com', 'Direct: 804-501-7523 / Mobile: 804-339-5497', null, 'Managing Director, Henrico Economic Development Authority', null, true, true, false, false, false),
  ('HENRICO COUNTY VA', 1, 'Linda McArdle', 'Business Manager', 'Linda@henrico.com', null, null, 'Henrico County Economic Dev. Authority', null, false, true, false, false, false),
  ('HENRICO COUNTY VA', 2, 'Joey Peppersack', null, 'Joey@Henrico.com', null, null, null, null, false, true, false, false, false),
  ('HENRICO COUNTY VA', 3, 'Ashley Kubat', 'Director of Administration', 'Ashley@henrico.com', 'Direct: 804-501-7523 / Mobile: 804-339-5497', null, 'Henrico County', null, false, false, true, false, false),
  ('HENRICO COUNTY VA', 4, 'Lane Bains', null, 'Lane@henrico.com', null, null, null, null, false, false, true, false, false),
  ('INVEST BUFFALO NIAGARA', 0, 'Matthew Hubacher', 'Vice President, Research', 'mhubacher@buffaloniagara.org', '716-359-0337', null, null, 'Invest Buffalo Niagara
The Brisbane Building', true, false, false, false, false),
  ('INVEST BUFFALO NIAGARA', 1, 'Olivia Hill', 'Senior Business Development Specialist', 'ohill@buffaloniagara.org', '800-916-9073', null, null, null, false, true, false, false, false),
  ('INVEST BUFFALO NIAGARA', 2, 'Mirka Arevalo', 'summer intern 2022', 'marevalo@buffaloniaagra.org', null, null, null, null, false, true, false, false, false),
  ('KANSAS CITY – Blue River Valley', 0, 'Marc Pollick', null, null, null, null, 'Giving Back Fund/Foundation for Regeneration', null, true, false, true, false, false),
  ('KANSAS CITY – Blue River Valley', 1, 'Brian Weinberg', 'Director', 'brian@regeneration.us', '817.228.8011', null, 'Foundation for Regeneration', 'Brian', false, true, true, false, false),
  ('KANSAS CITY – Blue River Valley', 2, 'Jim Erickson', 'Econ Dev Corp Kansas City', 'jerickson@edckc.com', null, null, null, null, false, true, false, false, false),
  ('KANSAS CITY – Blue River Valley', 3, 'Becca Castro', 'Econ Dev Corp Kansas City', 'bcastro@edckc.com', null, null, null, null, false, true, false, false, false),
  ('LUCAS COUNTY OH', 0, 'Matthew S. Heyrman', null, 'mheyrman@co.lucas.oh.us', '(419) 930-7786', null, 'Deputy County Administrator, Director of Economic Development, Board of Lucas County Commissioners', null, true, false, false, false, false),
  ('LUCAS COUNTY OH', 1, 'Josh Thurston', null, 'jthurston@co.lucas.oh.us', '(419) 213-3705 / (419) 681-5167', null, 'Business Engagement Specialist, Lucas County Department of Economic Development', null, false, true, false, false, false),
  ('LUCAS COUNTY OH', 2, 'Gina Kaczala', null, 'gkaczala@co.lucas.oh.us', '419.213.3710', null, 'Lucas County Economic Development Corp.', null, false, false, true, false, false),
  ('NETWORK KANSAS', 0, 'Steve Radley', null, 'Sradley@networkKansas.com', '877.521.8600', null, 'Network Kansas', null, true, false, false, false, true),
  ('NETWORK KANSAS', 1, 'Tiffany Nixon', null, 'tjnixon@networkKansas.com', '887.521.8600', null, 'Network Kansas', null, false, true, false, false, true),
  ('NETWORK KANSAS', 2, 'Kristi Pedersen', 'Dir Budget', 'kpedersen@networkKansas.com', '316.425.8808', null, null, null, false, false, true, false, false),
  ('NORTH CAROLINA STATE UNIVERSITY', 0, 'Barbara Williams', 'Associate Executive Dir.', 'Barbaral_williams@ncsu.edu', '919.515.2358', null, 'NCSU / Existing Industry Solutions', null, true, true, false, false, false),
  ('NORTH CAROLINA STATE UNIVERSITY', 1, 'Kevin Grayson', null, 'krgrayso@ncsu.edu', null, null, null, null, false, true, false, false, false),
  ('NORTH CAROLINA STATE UNIVERSITY', 2, 'Anna Mangum', null, 'aemangum@ncsu.edu', null, null, null, null, false, true, false, false, false),
  ('NORTH CAROLINA STATE UNIVERSITY', 3, 'Madelene Brooks', null, 'mmbrooks@ncsu.edu', '910.262.6470', null, 'NCSU / EIS Purchasing', null, false, false, true, false, false),
  ('OPPORTUNITY SQUARED (AREA 15 IOWA)', 0, 'Holly Berg', 'Executive Director', 'info@area15rpc.com', '641.684.6551', null, 'Opportunity Squared/ Area 15 Regional Planning Commission', null, true, false, false, false, false),
  ('OPPORTUNITY SQUARED (AREA 15 IOWA)', 1, 'Carla Eysink', 'Executive Director', 'ceysink@marioncountyiowa.gov', '641.828.2257', null, 'Marion County Development', null, false, true, true, false, false),
  ('OPPORTUNITY SQUARED (AREA 15 IOWA)', 2, 'Deann DeGroot', 'Executive Director, Mahaska County Chamber', 'ddegroot@mahaskacountychamber.com', '641.672.2591', null, null, null, false, true, false, false, false),
  ('RANCHO CORDOVA', 0, 'Diann Rogers', 'President', 'dhrogers@ranchocordova.org', '916.273.5706', null, 'Rancho Cordova Area Chamber of Commerce', null, true, true, true, false, false),
  ('RANCHO CORDOVA', 1, 'Cassandra Marcum', null, 'cmarcum@ranchocordova.org', '916-273-5703', null, null, null, false, true, false, false, false),
  ('RANCHO CORDOVA', 2, 'Mark Sanders', null, 'mark@berkeleystrategy.org', null, null, 'Berkeley Strategy', null, false, true, false, false, false),
  ('RICHARDSON, TEXAS', 0, 'Beth Kolman', 'Director Economic Development', 'beth@telecomcorridor.com', '972.792.2817', null, 'Richardson Chamber of Commerce', null, true, true, true, false, false),
  ('SAHUARITA, ARIZONA', 0, 'Victor Gonzalez', 'Economic Development Director', 'vgonzalez@sahuaritaaz.gov', '520.822.8817 / 520-822-8817', null, 'Town of Sahuarita, Arizona', null, true, true, true, false, false),
  ('SACRAMENTO', 0, 'Michael Young', null, 'mkyoung@cityofsacramento.org', 'Mobile: 916-541-6408', null, 'Development Project Manager, City of Sacramento, Office of Innovation and Economic Development', null, true, false, true, false, false),
  ('SACRAMENTO', 1, 'Kenny Sadler', null, 'kenny@berkeleystrategy.org', '916.832.2676', null, 'Berkeley Strategy Advisors', null, false, true, false, false, false),
  ('SACRAMENTO', 2, 'Craig Keys', null, 'Craig@berkeleystrategy.org', null, null, 'Berkeley Strategy Advisors', null, false, true, false, false, false),
  ('SACRAMENTO', 3, 'Jenny Davison', 'Executive Administrator', 'Jenny@berkeleystrategy.org', '916.226.7131', null, 'Berkeley Strategy', null, false, true, false, false, false),
  ('SACRAMENTO', 4, 'Aubree Taylor', null, 'ajtaylor@cityofsacramento.org', '916.808.7191', null, 'Office of Innovation and Econ Dev, City of Sacramento', null, false, false, true, false, false),
  ('SANDOVAL ECONOMIC ALLIANCE (NEW MEXICO)', 0, 'Fred Shepherd', 'President and CEO', 'Fred@sea-nm.com', '505.891.4305', null, 'Sandoval Economic Alliance', null, true, true, false, false, false),
  ('SANDOVAL ECONOMIC ALLIANCE (NEW MEXICO)', 1, 'Mikayla Standefer', 'Dir. of Business Development', 'Mikayla@sea-nm.com', '505.891.4305', null, 'Sandoval Economic Alliance', null, false, true, false, false, false),
  ('SANDOVAL ECONOMIC ALLIANCE (NEW MEXICO)', 2, 'Bridget Condon', 'Dir. of Research', 'Bridget@sea-nm.com', '505.891.4305', null, 'Sandoval Economic Alliance', null, false, true, false, false, false),
  ('SANDOVAL ECONOMIC ALLIANCE (NEW MEXICO)', 3, 'Deborah Breitfeld', null, 'deborah@sea-nm.com', null, null, null, null, false, true, false, false, false),
  ('SANDOVAL ECONOMIC ALLIANCE (NEW MEXICO)', 4, 'Helen Vanness', 'Office Manager', 'Helen@sea-nm.com', '505.891.4305', null, 'Sandoval Economic Alliance', null, false, false, true, false, false),
  ('SHENANDOAH VALLEY PARTNERSHIP (VIRGINIA)', 0, 'Jay Langston', 'Executive Director', 'jlangston@theshenandoahvalley.com', '540.568.3259', null, 'Shenandoah Valley Partnership', null, true, true, true, false, false),
  ('SUSSEX COUNTY, DELEWARE', 0, 'Michael Vincent', 'President', 'William.pfaff@sussexcountyde.gov', '302.855.770 / 302.855.7770', null, 'Sussex County Government', null, true, true, true, false, false),
  ('TRICITY, WASHINGTON', 0, null, null, null, '509.491.3234', null, '??', null, true, false, true, false, false),
  ('TRICITY, WASHINGTON', 1, null, null, 'info@tricityregionalchamber.com', '509.491.3234', null, '??', null, false, true, false, false, false),
  ('UTAH STATE UNIVERSITY EASTERN', 0, 'Ethan Migliori', 'Director Non-credit', 'Ethan.migliori@usu.edu', '435.613.5435', null, null, 'Utah State Univ Eastern', true, true, true, false, false),
  ('VIRGINIA ECONOMIC DEVELOPMENT PARTNERSHIP', 0, 'Shirley Dodson', 'Business Manager, Virginia Economic Development Partnership', 'sdodson@vedp.org', 'Office: 804.545.5719 / Cell: 804.584.9239', null, null, null, true, true, true, false, false),
  ('VIRGINIA ECONOMIC DEVELOPMENT PARTNERSHIP', 1, 'Andrew Larsen', null, 'Andrew@henrico.com', null, null, null, null, false, true, false, false, false),
  ('VIRGINIA ECONOMIC DEVELOPMENT PARTNERSHIP', 2, 'Jill Loope', 'Director', 'jloope@roanokecountyva.gov', '540.772.2124', null, 'Roanoke County Economic Development', null, false, true, false, false, false),
  ('WHITESIDE COUNTY, IL', 0, 'Gary Camarano', 'ED Dir', 'gcamarano@whiteside.org', '815.772.5182', null, 'Whiteside County ED', null, true, true, true, false, false),
  ('YORK, PENNSYLVANIA', 0, 'Skyler Yost', null, 'skyler@stelmocommunitybuilders.com', '717.318.4090', null, 'St. Elmo Community Builders', null, true, true, true, false, false);

-- Normalised for matching: uppercase, everything that isn't a letter or a
-- digit removed outright. Separators are dropped rather than collapsed to a
-- space so that "Tri-City", "Tri City" and "TRICITY" are all one string --
-- with spaces kept, the doc's "TRICITY" would miss a dashboard row spelled
-- "Tri-City Regional Chamber" and a duplicate Program would be created.
create or replace function pg_temp._n(t text) returns text language sql immutable as $$
  select regexp_replace(upper(coalesce(t, '')), '[^A-Z0-9]', '', 'g')
$$;

-- ---------------------------------------------------------------------------
-- STEP 1 -- LOOK BEFORE YOU IMPORT
-- ---------------------------------------------------------------------------
-- Run this SELECT on its own first. It writes nothing. One line per Program in
-- Chris's doc, showing which Program in the dashboard it will attach to.
--
--   MATCH   -- found it; contacts merge into that Program.
--   CREATE  -- no match, so a new Program gets created. Check these: if one is
--              really a Program you already have under a different name, say
--              so and the match phrase can be corrected instead of ending up
--              with two rows for the same Program.
--   AMBIGUOUS -- the phrase matches more than one Program; the import skips it.
--
-- Then run everything below it.
select
  p.doc_name                                       as "Program in the doc",
  case when count(c.id) = 0 then 'CREATE  (new Program)'
       when count(c.id) = 1 then 'MATCH'
       else 'AMBIGUOUS  (' || count(c.id) || ' matches -- will skip)' end
                                                   as "what happens",
  coalesce(string_agg(c.name || '  [' || c.code || ']', ' | '), '-')
                                                   as "existing Program(s)",
  (select count(*) from _imp_contact i where i.doc_name = p.doc_name)
                                                   as "people in the doc"
from _imp_program p
left join econ_dev_companies c
       on pg_temp._n(c.name) like '%' || pg_temp._n(p.match_phrase) || '%'
       or pg_temp._n(c.code) = pg_temp._n(p.code_hint)
group by p.doc_name
order by 2 desc, 1;

-- ---------------------------------------------------------------------------
-- STEP 2 -- THE IMPORT
-- ---------------------------------------------------------------------------

do $$
declare
  ip        _imp_program%rowtype;
  ic        _imp_contact%rowtype;
  pid       uuid;
  oid       uuid;
  cid       uuid;
  hits      int;
  new_code  text;
  n         int;
  created   int := 0;
  matched   int := 0;
  skipped   int := 0;
  c_ins     int := 0;
  c_upd     int := 0;
begin
  select organization_id into oid from econ_dev_companies limit 1;
  if oid is null then
    raise exception 'No Programs exist yet, so there is no organization to attach these to.';
  end if;

  for ip in select * from _imp_program order by doc_name loop
    select count(*) into hits from econ_dev_companies
     where pg_temp._n(name) like '%' || pg_temp._n(ip.match_phrase) || '%'
        or pg_temp._n(code) = pg_temp._n(ip.code_hint);

    if hits > 1 then
      skipped := skipped + 1;
      raise notice 'SKIPPED % -- "%" matches % Programs; rename one or import it by hand.',
        ip.doc_name, ip.match_phrase, hits;
      continue;
    end if;

    if hits = 1 then
      select id into pid from econ_dev_companies
       where pg_temp._n(name) like '%' || pg_temp._n(ip.match_phrase) || '%'
          or pg_temp._n(code) = pg_temp._n(ip.code_hint);
      matched := matched + 1;
    else
      -- Not in the dashboard. Greg chose to create these rather than skip them.
      new_code := ip.code_hint;
      n := 1;
      while exists (select 1 from econ_dev_companies where upper(code) = upper(new_code)) loop
        n := n + 1;
        new_code := ip.code_hint || n::text;
      end loop;
      insert into econ_dev_companies (organization_id, code, name, active)
      values (oid, new_code, ip.doc_name, true)
      returning id into pid;
      created := created + 1;
      raise notice 'CREATED Program % (code %)', ip.doc_name, new_code;
    end if;

    -- Program fields: fill blanks only, never overwrite.
    update econ_dev_companies set
      address_street = coalesce(nullif(btrim(address_street), ''), ip.street),
      address_city   = coalesce(nullif(btrim(address_city),   ''), ip.city),
      address_state  = coalesce(nullif(btrim(address_state),  ''), ip.state),
      address_zip    = coalesce(nullif(btrim(address_zip),    ''), ip.zip),
      phone          = coalesce(nullif(btrim(phone),          ''), ip.phone),
      notes          = coalesce(nullif(btrim(notes),          ''), ip.notes)
     where id = pid;

    for ic in select * from _imp_contact where doc_name = ip.doc_name order by seq loop
      cid := null;
      if ic.email is not null and btrim(ic.email) <> '' then
        select id into cid from econ_dev_partner_contacts
         where partner_id = pid and lower(btrim(email)) = lower(btrim(ic.email))
         order by sort_order limit 1;
      end if;
      if cid is null and ic.name is not null and btrim(ic.name) <> '' then
        select id into cid from econ_dev_partner_contacts
         where partner_id = pid and pg_temp._n(name) = pg_temp._n(ic.name)
         order by sort_order limit 1;
      end if;
      -- Neither name nor email: the doc's own "??" rows. Matching on the phone
      -- is the only handle left, and without it a re-run would insert them
      -- again every time.
      if cid is null and coalesce(btrim(ic.name), '') = '' and coalesce(btrim(ic.email), '') = ''
         and ic.phone is not null and btrim(ic.phone) <> '' then
        select id into cid from econ_dev_partner_contacts
         where partner_id = pid and coalesce(btrim(name), '') = ''
           and regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g')
             = regexp_replace(ic.phone, '[^0-9]', '', 'g')
         order by sort_order limit 1;
      end if;

      if cid is null then
        insert into econ_dev_partner_contacts (
          organization_id, partner_id, name, title, email, phone, address, notes, region,
          sort_order, is_primary_contact, is_program_administrator, is_program_finance,
          is_contract_signer, is_regional_director, include_on_cc)
        values (
          oid, pid, coalesce(ic.name, ''), ic.title, ic.email, ic.phone, ic.org, ic.notes, ic.region,
          coalesce((select max(sort_order) + 1 from econ_dev_partner_contacts where partner_id = pid), 0),
          ic.is_primary, ic.is_admin, ic.is_finance, false, ic.is_rd, ic.cc);
        c_ins := c_ins + 1;
      else
        update econ_dev_partner_contacts set
          name    = case when btrim(name) = '' then coalesce(ic.name, '') else name end,
          title   = coalesce(nullif(btrim(title),   ''), ic.title),
          email   = coalesce(nullif(btrim(email),   ''), ic.email),
          phone   = coalesce(nullif(btrim(phone),   ''), ic.phone),
          address = coalesce(nullif(btrim(address), ''), ic.org),
          notes   = coalesce(nullif(btrim(notes),   ''), ic.notes),
          region  = coalesce(nullif(btrim(region),  ''), ic.region),
          is_primary_contact       = is_primary_contact       or ic.is_primary,
          is_program_administrator = is_program_administrator or ic.is_admin,
          is_program_finance       = is_program_finance       or ic.is_finance,
          is_regional_director     = is_regional_director     or ic.is_rd,
          include_on_cc            = include_on_cc            or ic.cc
         where id = cid;
        c_upd := c_upd + 1;
      end if;
    end loop;
  end loop;

  raise notice '--------------------------------------------------------------';
  raise notice 'Programs: % matched, % created, % skipped', matched, created, skipped;
  raise notice 'Contacts: % added, % updated in place', c_ins, c_upd;
  raise notice '--------------------------------------------------------------';
end $$;

drop function if exists pg_temp._n(text);
drop table if exists _imp_program;
drop table if exists _imp_contact;
