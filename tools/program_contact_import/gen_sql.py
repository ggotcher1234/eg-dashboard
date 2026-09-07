# -*- coding: utf-8 -*-
import json, re, io

d = json.load(open('import/final.json'))

# The distinctive words to find each Program by, chosen by hand -- a generic
# similarity score would happily match "GREATER OMAHA" to "GREATER ROCHESTER".
MATCH = {
 'ADVANTAGE VALLEY (WEST VIRGINIA)': 'ADVANTAGE VALLEY',
 'ALLOY DEVELOPMENT': 'ALLOY',
 'ANNAPOLIS': 'ANNAPOLIS',
 'CABARRUS COUNTY, NORTH CAROLINA': 'CABARRUS',
 'ECONOMIC DEVELOPMENT PARTNERSHIP OF NORTH CAROLINA': 'PARTNERSHIP OF NORTH CAROLINA',
 'GREATER OMAHA CHAMBER': 'OMAHA',
 'GREATER ROCHESTER ENTERPRISE': 'ROCHESTER',
 'GROW KETCHIKAN': 'KETCHIKAN',
 'HENRICO COUNTY VA': 'HENRICO',
 'HONDO, TEXAS': 'HONDO',
 'INVEST BUFFALO NIAGARA': 'BUFFALO',
 'KANSAS CITY – Blue River Valley': 'BLUE RIVER',
 'LUCAS COUNTY OH': 'LUCAS',
 'NETWORK KANSAS': 'NETWORK KANSAS',
 'NORTH CAROLINA STATE UNIVERSITY': 'NORTH CAROLINA STATE UNIVERSITY',
 'NORTHWEST HILLS COUNCIL OF GOVERNMENTS': 'NORTHWEST HILLS',
 'OPPORTUNITY SQUARED (AREA 15 IOWA)': 'OPPORTUNITY SQUARED',
 'Penn-Northwest Development Corporation': 'PENNNORTHWEST',
 'RANCHO CORDOVA': 'RANCHO CORDOVA',
 'REXBURG, IDAHO': 'REXBURG',
 'RICHARDSON, TEXAS': 'RICHARDSON',
 'SAHUARITA, ARIZONA': 'SAHUARITA',
 'SACRAMENTO': 'SACRAMENTO',
 'SANDOVAL ECONOMIC ALLIANCE (NEW MEXICO)': 'SANDOVAL',
 'SHENANDOAH VALLEY PARTNERSHIP (VIRGINIA)': 'SHENANDOAH',
 'SUMMIT ECONOMIC PARTNERSHIP': 'SUMMIT',
 'SUSSEX COUNTY, DELEWARE': 'SUSSEX',
 'TRICITY, WASHINGTON': 'TRICITY',
 'UTAH STATE UNIVERSITY EASTERN': 'UTAH STATE',
 'VIRGINIA ECONOMIC DEVELOPMENT PARTNERSHIP': 'VIRGINIA ECONOMIC DEVELOPMENT',
 'WHITESIDE COUNTY, IL': 'WHITESIDE',
 'YORK, PENNSYLVANIA': 'YORK',
}

CODE = {
 'ADVANTAGE VALLEY (WEST VIRGINIA)': 'ADVVALLEY', 'ALLOY DEVELOPMENT': 'ALLOY',
 'ANNAPOLIS': 'ANNAPOLIS', 'CABARRUS COUNTY, NORTH CAROLINA': 'CABARRUS',
 'ECONOMIC DEVELOPMENT PARTNERSHIP OF NORTH CAROLINA': 'EDPNC',
 'GREATER OMAHA CHAMBER': 'OMAHA', 'GREATER ROCHESTER ENTERPRISE': 'GRE',
 'GROW KETCHIKAN': 'KETCHIKAN', 'HENRICO COUNTY VA': 'HENRICO', 'HONDO, TEXAS': 'HONDO',
 'INVEST BUFFALO NIAGARA': 'BUFFALO', 'KANSAS CITY – Blue River Valley': 'BLUERIVER',
 'LUCAS COUNTY OH': 'LUCAS', 'NETWORK KANSAS': 'NETKANSAS',
 'NORTH CAROLINA STATE UNIVERSITY': 'NCSU', 'NORTHWEST HILLS COUNCIL OF GOVERNMENTS': 'NWHILLS',
 'OPPORTUNITY SQUARED (AREA 15 IOWA)': 'OPPSQUARED',
 'Penn-Northwest Development Corporation': 'PENNNW', 'RANCHO CORDOVA': 'RANCHO',
 'REXBURG, IDAHO': 'REXBURG', 'RICHARDSON, TEXAS': 'RICHARDSON', 'SAHUARITA, ARIZONA': 'SAHUARITA',
 'SACRAMENTO': 'SACRAMENTO', 'SANDOVAL ECONOMIC ALLIANCE (NEW MEXICO)': 'SANDOVAL',
 'SHENANDOAH VALLEY PARTNERSHIP (VIRGINIA)': 'SHENANDOAH', 'SUMMIT ECONOMIC PARTNERSHIP': 'SUMMIT',
 'SUSSEX COUNTY, DELEWARE': 'SUSSEX', 'TRICITY, WASHINGTON': 'TRICITY',
 'UTAH STATE UNIVERSITY EASTERN': 'USUE', 'VIRGINIA ECONOMIC DEVELOPMENT PARTNERSHIP': 'VEDP',
 'WHITESIDE COUNTY, IL': 'WHITESIDE', 'YORK, PENNSYLVANIA': 'YORK',
}


def q(v):
    if v is None or v == '':
        return 'null'
    return "'" + str(v).replace("'", "''") + "'"


def b(v):
    return 'true' if v else 'false'


rows_p, rows_c = [], []
for r in d['programs']:
    name = r['program']
    rows_p.append("  (%s, %s, %s, %s, %s, %s, %s, %s, %s)" % (
        q(name), q(MATCH[name]), q(CODE[name]),
        q(r['street']), q(r['city']), q(r['state']), q(r['zip']), q(r['phone']),
        q('\n'.join(r['notes']))))
    for i, p in enumerate(r['people']):
        rows_c.append("  (%s, %d, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)" % (
            q(name), i, q(p['name']), q(p['title']), q(p['email']), q(p['phone_str']),
            q(p['region']), q(p['org'] or None), q('\n'.join(p['notes']) or None),
            b(p['roles']['primary']), b(p['roles']['admin']), b(p['roles']['finance']),
            b(p['regional']), b(p['cc'] is True)))

sql = """-- 113_import_program_contacts.sql
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
%s;

insert into _imp_contact values
%s;

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
       on pg_temp._n(c.name) like '%%' || pg_temp._n(p.match_phrase) || '%%'
       or pg_temp._n(c.code) = pg_temp._n(p.code_hint)
group by p.doc_name
order by 2 desc, 1;

-- ---------------------------------------------------------------------------
-- STEP 2 -- THE IMPORT
-- ---------------------------------------------------------------------------

do $$
declare
  ip        _imp_program%%rowtype;
  ic        _imp_contact%%rowtype;
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
     where pg_temp._n(name) like '%%' || pg_temp._n(ip.match_phrase) || '%%'
        or pg_temp._n(code) = pg_temp._n(ip.code_hint);

    if hits > 1 then
      skipped := skipped + 1;
      raise notice 'SKIPPED %% -- "%%" matches %% Programs; rename one or import it by hand.',
        ip.doc_name, ip.match_phrase, hits;
      continue;
    end if;

    if hits = 1 then
      select id into pid from econ_dev_companies
       where pg_temp._n(name) like '%%' || pg_temp._n(ip.match_phrase) || '%%'
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
      raise notice 'CREATED Program %% (code %%)', ip.doc_name, new_code;
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
  raise notice 'Programs: %% matched, %% created, %% skipped', matched, created, skipped;
  raise notice 'Contacts: %% added, %% updated in place', c_ins, c_upd;
  raise notice '--------------------------------------------------------------';
end $$;

drop function if exists pg_temp._n(text);
drop table if exists _imp_program;
drop table if exists _imp_contact;
""" % (',\n'.join(rows_p), ',\n'.join(rows_c))

io.open('import/113_import_program_contacts.sql', 'w', encoding='utf-8').write(sql)
print('wrote', len(sql), 'bytes;', len(rows_p), 'programs,', len(rows_c), 'contacts')
