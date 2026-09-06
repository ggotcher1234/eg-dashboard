-- 112_program_contact_cc_flag.sql
--
-- Depends on 089_program_contact_structured_fields.sql (which added the
-- `category` enum column to econ_dev_partner_contacts and folded all four
-- kinds of Program contact into that one structured table).
--
-- Greg (9/6/26): "a mini business card view for each person and a dropdown
-- in the business card that selects which role they fit and a checkbox if
-- they should be on the cc list."
--
-- That splits one thing into two. Today "CC List" is a fourth CATEGORY,
-- mutually exclusive with Contract Signer / Program Administrator /
-- Program Finance -- so a Program Administrator who should also be CC'd has
-- to be entered twice, once in each bucket. After this migration, role and
-- CC-membership are independent: `category` says what someone DOES, and the
-- new `include_on_cc` says whether they get copied. Any contact in any role
-- can be flagged, and the checkbox is the only way to say so.
--
-- WHAT HAPPENS TO EXISTING 'cc_list' ROWS
-- They become Program Administrators with include_on_cc = true. That is a
-- lossless move -- name/title/address/email/phone/notes are untouched, only
-- the bucket changes -- but it is a judgement call, and it is the one place
-- this migration guesses: a CC-List-only person has no stated role, and
-- Program Administrator is the closest of the three ("day-to-day contact for
-- this Program"). Nothing prevents re-filing them from the dropdown after.
--
-- EXPECT SOME DUPLICATES. Where the same human was already entered twice --
-- once as, say, Program Administrator and again under CC List -- this leaves
-- two Program Administrator cards for that person, one with the CC box
-- ticked. They are NOT merged automatically: matching people by name or
-- email across free-typed rows is exactly the kind of guess 089 refused to
-- make, and a wrong merge silently destroys a phone number or a note. Both
-- rows stay visible in the new card grid so whoever spots the pair can
-- delete the redundant one deliberately.
--
-- The 'cc_list' enum VALUE is deliberately left in
-- partner_contact_category_type. Dropping a value from a Postgres enum
-- means rebuilding the type and every column using it, and it buys nothing:
-- after the backfill no row references it, and leaving it means this
-- migration can be reverted by flipping the categories back. The UI simply
-- stops offering it.
--
-- Safe to re-run. The backfill only touches rows still sitting in
-- 'cc_list', so a second run is a no-op.

alter table econ_dev_partner_contacts
  add column if not exists include_on_cc boolean not null default false;

comment on column econ_dev_partner_contacts.include_on_cc is
  'Whether this contact is copied on Program correspondence. Independent of `category` (their role). Replaces the old category = ''cc_list'' bucket as of 112.';

-- Backfill: every remaining CC-List contact becomes a CC-flagged Program
-- Administrator. Ordering is preserved -- sort_order is not touched, and the
-- app treats the first CC-flagged contact in sort order as the Program's
-- "Primary Contact", which is the same rule the CC List had before.
update econ_dev_partner_contacts
   set category      = 'program_administrator',
       include_on_cc = true
 where category = 'cc_list';

-- Index the flag: the Programs list resolves a Primary Contact for every
-- row on render, which is one CC lookup per Program on every page load.
create index if not exists econ_dev_partner_contacts_cc_idx
  on econ_dev_partner_contacts (partner_id, include_on_cc)
  where include_on_cc;
