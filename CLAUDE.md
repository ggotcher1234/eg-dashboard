# EG Dashboard (EGDB)

Multi-client management app for running an Economic Gardening program: engagements,
client applications, research, team roster and allocations, hours, and invoicing —
plus public-facing client dashboards and forms.

Owner: Greg Gotcher (Leadforce Solutions). Deployed on Netlify. Backend is Supabase.

---

## Architecture — read this before changing anything

**There is no build step, no framework, no bundler, and no npm install.** Every page is
a single self-contained `.html` file at the repo root with its own inline `<style>` and
inline `<script>`. Supabase is loaded from the CDN as a UMD global:

```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.js"></script>
```

Each page creates its own client (`SUPABASE_URL` + anon key are inline in every file —
both are public by design; RLS is what enforces access). Editing a file and pushing to
`main` is the deploy. Do not introduce a toolchain, a shared `app.js`, or a CSS file
unless Greg explicitly asks — the standalone-page design is deliberate.

**The consequence that matters: shared UI is copy-pasted, not imported.** The site
header and nav exist independently in all 15 admin pages. A nav change is a 15-file
change, and every one of them has to be edited or the nav silently diverges between
pages. Same for the design tokens in `:root` and the `.nav-*` CSS block.

---

## Page inventory

**Admin pages (authenticated, carry `<nav class="site-nav">`) — 15 files.**
Any nav or header edit touches every one of these:

```
index.html                      Engagements list — the app's home
client_workspace.html           Engagement Workspace (per-client hub)
client_control_center.html      Client Control Center ("ccc")
client_profile.html             Client Info / Info Wizard
client_research.html            Research questions + docs
client_workflow_files.html      Workflow document uploads
client_applications.html        Applications admin
client_cumulative_hours.html    Hours rollup
econ_dev_partners_admin.html    Programs (econ dev partners) admin
program_application_links.html  Public application links per program
team_directory.html             Roster
invoicing_report.html           Time Sheets
program_invoicing.html          Program Invoices
specialist_invoices.html        Pay Statements
resource_templates.html         Resource Vault templates
```

**Public / standalone pages (no site-nav, no auth or token-scoped):**

```
client_public.html                 Public client dashboard (also served at /c/:slug)
client_application_public.html     Public application form
controlling_document.html          Controlling doc (admin view)
controlling_document_public.html   Controlling doc (client view)
evaluation.html                    Close-out evaluation (admin)
evaluation_public.html             Close-out evaluation (client)
discovery_call_notes.html          Discovery call notes
reset_password.html                Password reset
```

Sub-apps under their own folders: `feedme/extremis/` and `listening-post/clippard/`
(single-file RSS/signal readers with a `config.js` and OPML feed lists — separate
products that happen to live in this repo).

---

## Top nav — current structure and patterns

```
Applications ▾   dynamic dropdown, button-only, populated at runtime (hidden until it has items)
Engagements      plain link → index.html
Programs ▾       SPLIT ITEM → econ_dev_partners_admin.html
                   ├ Add Program           (econ_dev_partners_admin.html?action=add)
                   └ Application Links     (program_application_links.html)
Roster ▾         SPLIT ITEM → team_directory.html
                   └ Add Roster Member     (team_directory.html?action=add)
Invoicing ▾      button-only dropdown
                   ├ Time Sheets           (invoicing_report.html)
                   ├ Program Invoices      (program_invoicing.html)
                   └ Pay Statements        (specialist_invoices.html)
```

**Split-item pattern** (`.nav-split-item`) — use this when the nav label must stay a real
link *and* have a menu. A plain dropdown-toggle `<button>` with no `href` breaks direct
navigation, which is why Programs and Roster are built this way:

```html
<div class="nav-item-dropdown nav-split-item">
  <a href="team_directory.html" class="nav-link">Roster</a>
  <button type="button" class="nav-link-dropdown-btn nav-caret-only" aria-label="Roster menu">
    <span class="nav-caret">&#9662;</span>
  </button>
  <div class="nav-submenu">
    <a href="team_directory.html?action=add">Add Roster Member</a>
  </div>
</div>
```

**Submenus open on hover** above 900px (`.nav-item-dropdown:hover .nav-submenu`), with a
`::before` strip bridging the 8px gap so the pointer doesn't fall through on the way
down. Click-to-open still works. Below 900px the nav collapses behind `.nav-toggle`,
submenus render inline and always-expanded, and `.nav-caret-only` is hidden.

**`?action=` deep-link pattern.** Actions that used to be in-page toolbar buttons now
live in the nav, so they must work from any page. The pattern (see `team_directory.html`):

1. Nav link points at `page.html?action=add`.
2. On that page, `applyActionDeepLink()` runs after auth/profile load, reads the param,
   and opens the modal if the user's role allows it.
3. A click handler on `a[href="page.html?action=add"]` intercepts the click *on that same
   page* and opens the modal directly, instead of doing a pointless full reload.

When an action moves into the nav, **delete the old in-page button** (markup, the
`classList.toggle("hidden", …)` role gating, and the listener). Leaving both means the
same action exists in two places and they drift.

---

## Roles

`super_admin`, `team_lead`, `specialist`, `program_admin`. Gating is done client-side by
toggling a `.hidden` class after the profile loads (`profile.role === "super_admin"`),
and enforced for real by Supabase RLS. Client-side gating is UX only — never treat it as
the security boundary.

---

## Supabase

Project: `ezujkumaxevuevlxtrxd.supabase.co`

**Edge functions** in `supabase/functions/`:

```
eg-dashboard-ai              powers the "Ask AI" drawer on admin pages
admin-create-team-member     roster member creation
enrich-from-website          Info Wizard auto-fill (Brandfetch Brand API when a key is set)
public-submit-application    public application form intake
public-submit-evaluation     public close-out evaluation intake
public-submit-controlling-doc public controlling-document responses
```

**Migrations** are flat numbered `.sql` files at the repo root: `NNN_description.sql`,
currently through `112`. They are applied by hand in the Supabase SQL editor — there is
no migration runner, so a file in the repo is not proof it has been run.

Gotchas in the existing sequence (leave them alone, just don't repeat the pattern):
`053`–`055` are missing, and `063` and `106` are each used twice
(`063_public_view_program_name` / `063_user_company_name`,
`106_application_status_archived` / `106_program_setup_fee`).
**Pick the next unused number and check for a collision before writing one.**

Note the recurring `*_fix_public_view_regression.sql` files (`036`, `064`): the public
client view is a wide denormalized view that breaks whenever a column is added upstream.
If you add a field that should surface on `client_public.html`, expect to update that
view too.

---

## Design tokens

Defined in `:root` in every page — keep them identical across files:

```css
--navy: #14304d;      --navy-light: #1f4a75;
--accent: #5c7248;    --accent-dark: #46592f;
--amber: #a9740f;
--danger: #b3403a;    --danger-dark: #922f2b;
--bg: #f4f6f8;        --card: #ffffff;
--border: #dde3e9;    --text: #1f2937;      --muted: #6b7280;
```

Print styles matter — several pages have `@media print` blocks that hide nav, drawers,
and action columns. If you remove an element that's listed in a print block's selector
list, remove it from that list too.

---

## Netlify

`netlify.toml` holds one rewrite that shortens client dashboard links:

```
/c/:slug  →  /client_public.html?slug=:slug   (200, rewrite not redirect)
```

Purely additive — the old `?slug=` links still work.

---

## Working conventions

- **One change per commit.** Greg works incrementally and reviews as he goes. Don't
  bundle unrelated edits; don't refactor adjacent code you weren't asked to touch.
- **Commit messages are short and imperative** — "update roster menu", "menu hover",
  "Info Wizard: Auto-fill button on the Description step too".
- **Comment the *why*, dated and attributed**, right where the non-obvious decision
  lives. This is the house style and it is worth matching:

  ```js
  // Opened from the top-nav Roster dropdown now that the toolbar button is
  // gone (Greg, 9/6/26). That link is ?action=add so it works as a real
  // destination from any other page; clicked from THIS page it would just be
  // a pointless reload, so the click is intercepted and this is called instead.
  ```

- **`main` is the deploy branch.** Commits go straight to `main`; a push is a release.
- When editing a repeated block (nav, tokens, print rules), change **every** admin page
  in the same commit and verify the count — `grep -c` across `*.html` is the quick check.
