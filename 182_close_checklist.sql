-- 182: the close-out checklist, and who closed an engagement.
--
-- Greg (11/1/26): "add a 3rd button called Close Engagement which will take
-- you to a checklist of things to check-off before you can click close."
--
-- Most of that checklist needs no storage at all. Whether the Controlling
-- Document is on file, whether every research question is complete, whether
-- the Evaluation Sheet came back -- the app already knows, so close_engagement
-- .html reads those and ticks them itself. A tick nobody can forge is worth
-- more than one somebody clicked through.
--
-- What is left is the handful of things that happen outside this app: the
-- final invoice, the word to the Program Administrator, a last look at what
-- the CEO sees. Those are a human's word, and this table is where that word
-- is kept.
--
-- A row per (engagement, item) with a boolean rather than insert/remove, so
-- unticking is an update and the table never needs a destructive policy.
-- checked_at / checked_by survive an untick on purpose: "Julie ticked this on
-- the 3rd and unticked it on the 5th" is the question somebody asks later.

create table if not exists public.client_close_checklist (
  client_id uuid not null references public.clients(id),
  item_key text not null,
  checked boolean not null default false,
  checked_at timestamptz,
  checked_by uuid references public.users(id),
  primary key (client_id, item_key)
);

alter table public.client_close_checklist enable row level security;

-- Same rule as every other per-engagement table: your engagements, or
-- anything if you are an Admin. A Team Lead ticks the items; only an Admin
-- presses Close (Greg, 11/1/26: "Admins only"), and that part is enforced
-- by the clients table's own update policy, not here.
create policy client_close_checklist_select on public.client_close_checklist
  for select using (is_super_admin() or is_assigned_to_client(client_id));

create policy client_close_checklist_insert on public.client_close_checklist
  for insert with check (is_super_admin() or is_assigned_to_client(client_id));

create policy client_close_checklist_update on public.client_close_checklist
  for update using (is_super_admin() or is_assigned_to_client(client_id))
  with check (is_super_admin() or is_assigned_to_client(client_id));

-- clients already had closed_at and date_closed and no record of who did it.
-- Closing is the one irreversible thing on an engagement, so it gets a name
-- against it like archiving a roster member does.
alter table public.clients add column if not exists closed_by uuid references public.users(id);
