-- Enough of the real schema to exercise 112 + 113 end to end.
create table organizations (id uuid primary key default gen_random_uuid(), name text);
create type partner_contact_category_type as enum ('cc_list','contract_signer','program_administrator','program_finance');
create table econ_dev_companies (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  code text not null, name text not null, active boolean not null default true,
  physical_address text, billing_hourly_rate numeric, archived boolean not null default false,
  created_at timestamptz not null default now()
);
create table econ_dev_partner_contacts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  partner_id uuid not null references econ_dev_companies(id) on delete cascade,
  name text not null, title text, email text, phone text,
  active boolean not null default true, sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  category partner_contact_category_type not null default 'cc_list',
  address text, notes text
);

insert into organizations (id, name) values ('11111111-1111-1111-1111-111111111111','EG');

-- Programs already in the dashboard, deliberately spelled the way Greg's app
-- might spell them rather than the way the doc does.
insert into econ_dev_companies (organization_id, code, name, physical_address) values
 ('11111111-1111-1111-1111-111111111111','GRE','Greater Rochester Enterprise','100 Chestnut Street, Ste 1910, Rochester NY'),
 ('11111111-1111-1111-1111-111111111111','ALLOY','Alloy Development', null),
 ('11111111-1111-1111-1111-111111111111','ANNAP','City of Annapolis', null),
 ('11111111-1111-1111-1111-111111111111','TRI','Tri-City Regional Chamber', null),
 ('11111111-1111-1111-1111-111111111111','ADV','Advantage Valley', null),
 ('11111111-1111-1111-1111-111111111111','EDPNC','Economic Development Partnership of NC', null),
 ('11111111-1111-1111-1111-111111111111','SUSSEX','Sussex County, Delaware', null);

-- Contacts already there: one exact-email match, one name-only match, one the
-- doc knows nothing about (must survive untouched), one with a phone the doc
-- would otherwise overwrite (must keep its own).
insert into econ_dev_partner_contacts (organization_id, partner_id, name, title, email, phone, category, sort_order)
select '11111111-1111-1111-1111-111111111111', id, v.name, v.title, v.email, v.phone, v.cat::partner_contact_category_type, v.so
from econ_dev_companies c
join (values
  ('GRE','Matt Hurlbutt','Chief Executive','matt@rochesterbiz.com','585.555.0000','contract_signer',0),
  ('GRE','Someone Local',null,'local@rochesterbiz.com',null,'cc_list',1),
  ('ALLOY','Harry Blanton',null,null,null,'program_administrator',0),
  ('ADV','Terrell Ellis',null,'terrell@advantagevalley.com',null,'cc_list',0)
) as v(code,name,title,email,phone,cat,so) on v.code = c.code;
