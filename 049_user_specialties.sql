-- 049_user_specialties.sql
--
-- Greg's "EG Team List Rules": each email is its own member card, each
-- email has exactly one role (admin / team_lead / consultant), but an
-- email can have MULTIPLE specialties -- e.g. an Admin-role account can
-- still be Team Lead on one engagement and Digital Marketing on another.
-- The existing users.default_specialty column only ever held one value;
-- the CSV importer already had to collapse multiple detected positions
-- down to a single "winner" via SPECIALTY_PRIORITY, which is exactly the
-- limitation this table removes.
--
-- "Admin" is deliberately NOT a valid specialty here (Greg: drop it --
-- being an Admin is a role, not a work area). "Team Lead" IS kept as a
-- specialty, distinct from the team_lead ROLE, since a person's account
-- role and their per-engagement capability aren't the same thing.
--
-- One row per (user, specialty) pair. organization_id is denormalized
-- from the parent user at insert time -- same tradeoff
-- econ_dev_partner_contacts (039) makes, to avoid a join to `users` on
-- every RLS check.
--
-- Write access matches how specialty edits already work in the app: the
-- person themselves or a Super Admin (same as title/about/phone on the
-- profile form) -- NOT locked to Super-Admin-only the way the role field
-- is on the account itself.
--
-- users.default_specialty is left in place for now (not dropped/renamed)
-- so this migration is non-destructive. The app is being updated to stop
-- reading/writing that column in favor of this table; a follow-up
-- migration can drop the old column once that's confirmed shipped.
--
-- Safe to re-run.

create table if not exists user_specialties (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  user_id         uuid not null references users(id) on delete cascade,
  specialty       text not null,
  created_at      timestamptz not null default now(),
  unique (user_id, specialty)
);

create index if not exists user_specialties_user_id_idx on user_specialties(user_id);
create index if not exists user_specialties_org_idx on user_specialties(organization_id);

alter table user_specialties enable row level security;

drop policy if exists user_specialties_select on user_specialties;
create policy user_specialties_select on user_specialties for select
using ( is_org_member(organization_id) or is_super_admin() );

drop policy if exists user_specialties_write on user_specialties;
create policy user_specialties_write on user_specialties for all
using ( user_id = auth.uid() or is_super_admin() )
with check ( user_id = auth.uid() or is_super_admin() );

-- Backfill: carry each user's existing single default_specialty forward
-- as their first specialty tag, so nobody's current specialty disappears
-- when the app switches over to reading from this table. Skips "admin"
-- (no longer a valid specialty value) and blanks.
--
-- default_specialty turns out to be a Postgres enum (specialty_type), not
-- plain text -- comparing it to '' errors (22P02: invalid input value for
-- enum), since '' was never a real member of that enum to begin with; a
-- blank specialty is already represented as NULL, which "is not null"
-- alone correctly excludes. Cast to text explicitly for the insert and
-- for the 'admin' comparison so this doesn't depend on an implicit cast.
insert into user_specialties (organization_id, user_id, specialty)
select u.organization_id, u.id, u.default_specialty::text
from users u
where u.default_specialty is not null
  and u.default_specialty::text <> 'admin'
on conflict (user_id, specialty) do nothing;
