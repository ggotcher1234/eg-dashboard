/* role_view.js -- the app's shared header script. Mostly "View as"; also the
 * two FAQ links in the account menu (Greg, 11/6/26), which are here for the
 * same reason everything else is: fourteen pages, one copy.
 *
 * "View as" -- Greg (10/6/26):
 *   "i don't want to have 3 logins but since i have to test for Admin, TL and
 *    Specialist i've created 3 logins. That needs to change. i need to have
 *    one login - Admin, but i need to change my view to TL or Specialist to
 *    see what they see."
 *
 * This is the FIRST shared script in the app -- every other page is
 * self-contained by design. It earns the exception because it has to behave
 * identically on fourteen pages and will be edited again; fourteen pasted
 * copies of this would drift within a month.
 *
 * The switch is NOT cosmetic. 145b teaches is_super_admin() about an active
 * role_view_overrides row, and 69 RLS policies call that function, so while an
 * override is live the DATABASE answers as a Team Lead or Specialist: the
 * engagement list scopes itself, writes are genuinely refused, Programs is
 * genuinely read-only. All this file does is keep the interface honest about
 * the same fact, and give you a way out.
 *
 * Two guarantees, both enforced in SQL rather than here:
 *   - an override can only point DOWN; a Specialist cannot grant themselves
 *     anything by writing a row (145b, and the clamp in 145c).
 *   - you cannot lock yourself out: the RLS on role_view_overrides keys on
 *     user_id = auth.uid() with no role test, so clearing your own override
 *     never needs the privilege the override took away. Rows also expire on
 *     their own.
 */
(function () {
  "use strict";

  var LABEL = { super_admin: "Admin", team_lead: "Team Lead", consultant: "Specialist" };
  // Greg (10/6/26): "i will rarely use the team lead and specialist views.
  // just for a few troubleshooting or to create training videos." A short
  // timer was protection against a forgotten override -- but a deliberate,
  // occasional switch is far likelier to be interrupted by the clock than
  // saved by it, and admin menus reappearing halfway through a recording is
  // worse than the thing the timer was guarding. The real protection was
  // never the clock: it is the RLS rule that lets you clear your own
  // override whatever role you are wearing.
  var HOURS = 12;

  function styles() {
    if (document.getElementById("rv-styles")) return;
    var css = document.createElement("style");
    css.id = "rv-styles";
    css.textContent = [
      // Greg (11/6/26): "move the Viewing as pill down a row and to the
      // right so it's not overlapping the menu." In #userbox it shared a
      // line with the nav, and on a wide nav the two met in the middle. Its
      // own row under the header cannot collide with anything.
      ".rv-chip-row{display:flex;justify-content:flex-end;padding:10px 28px 0;}",
      "@media(max-width:900px){.rv-chip-row{padding:8px 14px 0;}}",
      ".rv-chip{display:inline-flex;align-items:center;gap:7px;background:#a9740f;color:#fff;",
      "border-radius:999px;padding:3px 5px 3px 11px;font-size:11.5px;font-weight:700;",
      "letter-spacing:.2px;white-space:nowrap;flex-shrink:0;}",
      ".rv-chip button{background:rgba(255,255,255,.22);color:#fff;border:none;border-radius:999px;",
      "width:18px;height:18px;line-height:1;font:inherit;font-size:12px;cursor:pointer;padding:0;}",
      ".rv-chip button:hover{background:#fff;color:#7a5c17;}",
      ".pd-viewas{padding:6px 10px 8px;border-bottom:1px solid var(--border,#e2e8f0);margin-bottom:4px;}",
      ".pd-viewas-label{font-size:10.5px;font-weight:700;letter-spacing:.5px;text-transform:uppercase;",
      "color:var(--muted,#64748b);margin-bottom:5px;}",
      ".pd-viewas button{display:block;width:100%;text-align:left;padding:6px 8px;border-radius:6px;",
      "border:none;background:none;font:inherit;font-size:12.5px;color:var(--text,#0f172a);cursor:pointer;}",
      ".pd-viewas button:hover{background:#eef1f4;}",
      ".pd-viewas button[aria-current=\"true\"]{font-weight:700;background:#eef1f4;}",
      // Greg (11/6/26): "what if we add the Specialist FAQ's and Team Lead
      // FAQ's on the dropdown menu with change password and Sign Out. That
      // way they are out of the way and not part of the primary systems but
      // easily accessable long after you've lost the email links to them."
      ".pd-help{border-top:1px solid var(--border,#e2e8f0);margin-top:4px;padding-top:4px;}",
      ".pd-help a{display:block;padding:6px 10px;border-radius:6px;text-decoration:none;",
      "font-size:12.5px;color:var(--text,#0f172a);}",
      ".pd-help a:hover{background:#eef1f4;}",
      "@media print{.rv-chip-row{display:none;}}"
    ].join("");
    document.head.appendChild(css);
  }

  // A chip rather than the full-width bar it started as. Greg records
  // training videos in these views, and a banner reading "your Admin rights
  // are off" would sit in every frame of a video whose whole point is to look
  // like an ordinary Team Lead's screen. Small, in the header beside the
  // account menu, with its own exit -- still impossible to miss if you look,
  // easy to ignore on camera.
  function chip(viewing, onExit) {
    if (document.querySelector(".rv-chip")) return;
    var el = document.createElement("span");
    el.className = "rv-chip no-print";
    el.title = "You are viewing the dashboard as a " + (LABEL[viewing] || viewing) +
               ". Your Admin rights are off until you exit.";
    el.appendChild(document.createTextNode("Viewing as " + (LABEL[viewing] || viewing)));
    var x = document.createElement("button");
    x.type = "button";
    x.setAttribute("aria-label", "Exit this view and go back to Admin");
    x.innerHTML = "&times;";
    x.addEventListener("click", onExit);
    el.appendChild(x);
    // Its own row, right-aligned, directly under the header (Greg,
    // 11/6/26). It used to sit inside #userbox, which put it on the same
    // line as the nav -- fine on a narrow nav, overlapping Roster on a wide
    // one. No header on the page is fixed or sticky, so a row after it
    // simply pushes the page down by its own height.
    var row = document.createElement("div");
    row.className = "rv-chip-row no-print";
    row.appendChild(el);
    var header = document.querySelector("header");
    if (header && header.parentNode) header.insertAdjacentElement("afterend", row);
    else document.body.insertBefore(row, document.body.firstChild);
  }

  // Everyone gets these, whatever their role and whether or not they have
  // anything to switch views to -- which is why this runs on its own at DOM
  // ready rather than from mount(), where it would reach Admins only.
  //
  // This file is the app's one shared script, so a second one-purpose file
  // loaded into the same fourteen pages would be the drift it exists to
  // avoid. It is no longer only about "View as"; the comment at the top
  // says so.
  var HELP_LINKS = [
    { href: "faq_specialists.html", label: "Specialist FAQ" },
    { href: "faq_team_leads.html", label: "Team Lead FAQ" }
  ];

  function helpLinks() {
    var dd = document.getElementById("profile-dropdown");
    if (!dd || dd.querySelector(".pd-help")) return;
    styles();
    var box = document.createElement("div");
    box.className = "pd-help";
    HELP_LINKS.forEach(function (l) {
      var a = document.createElement("a");
      a.href = l.href;
      a.textContent = l.label;
      box.appendChild(a);
    });
    // Above Change Password: the two sign-in actions stay together at the
    // bottom, where muscle memory expects Sign out to be last.
    var pw = document.getElementById("change-password-btn");
    if (pw) pw.insertAdjacentElement("beforebegin", box);
    else dd.appendChild(box);
  }

  function menu(current, realRole, onPick) {
    var dd = document.getElementById("profile-dropdown");
    if (!dd || dd.querySelector(".pd-viewas")) return;
    var box = document.createElement("div");
    box.className = "pd-viewas";
    box.innerHTML = '<div class="pd-viewas-label">View as</div>';
    ["super_admin", "team_lead", "consultant"].forEach(function (r) {
      var b = document.createElement("button");
      b.type = "button";
      b.textContent = LABEL[r];
      if (r === current) b.setAttribute("aria-current", "true");
      b.addEventListener("click", function (e) { e.stopPropagation(); onPick(r); });
      box.appendChild(b);
    });
    var roleLine = dd.querySelector(".pd-role");
    if (roleLine) roleLine.insertAdjacentElement("afterend", box);
    else dd.insertBefore(box, dd.firstChild);
  }

  // Called by each page right after it loads its own profile row, BEFORE
  // anything reads profile.role -- that ordering is the whole trick, because
  // it means every existing isSuperAdmin check and every
  // [data-super-admin-only] toggle follows the override untouched.
  async function mount(sb, profile) {
    if (!sb || !profile) return profile;
    var realRole = profile.role;
    var effective = realRole;
    try {
      var res = await sb.rpc("my_effective_role");
      if (res && !res.error && res.data) effective = res.data;
    } catch (e) { /* fall back to the real role; never block the page */ }
    profile.role = effective;

    // Only someone who actually holds Admin has anything to switch away from.
    if (realRole !== "super_admin") return profile;

    styles();

    async function set(role) {
      if (role === realRole) return clear();
      var expires = new Date(Date.now() + HOURS * 3600 * 1000).toISOString();
      var r = await sb.from("role_view_overrides").upsert(
        { user_id: profile.id, effective_role: role, started_at: new Date().toISOString(), expires_at: expires },
        { onConflict: "user_id" }
      );
      if (r.error) { alert("Couldn't switch view: " + r.error.message); return; }
      location.reload();
    }
    async function clear() {
      // Expire rather than delete: it is one statement either way, and the
      // row left behind is a record of what was switched on and when.
      var r = await sb.from("role_view_overrides")
        .update({ expires_at: new Date().toISOString() })
        .eq("user_id", profile.id);
      if (r.error) { alert("Couldn't exit the view: " + r.error.message); return; }
      location.reload();
    }

    menu(effective, realRole, set);
    if (effective !== realRole) chip(effective, clear);
    return profile;
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", helpLinks);
  } else {
    helpLinks();
  }

  window.EGRoleView = { mount: mount, LABEL: LABEL, helpLinks: helpLinks };
})();
