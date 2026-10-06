/* role_view.js -- "View as" for the EG Dashboard.  Greg (10/6/26):
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
  var HOURS = 2;

  function styles() {
    if (document.getElementById("rv-styles")) return;
    var css = document.createElement("style");
    css.id = "rv-styles";
    css.textContent = [
      ".rv-bar{position:sticky;top:0;z-index:200;display:flex;align-items:center;justify-content:center;",
      "gap:14px;flex-wrap:wrap;padding:8px 16px;background:#a9740f;color:#fff;font-size:13px;font-weight:600;}",
      ".rv-bar button{background:#fff;color:#7a5c17;border:none;border-radius:999px;padding:5px 14px;",
      "font:inherit;font-weight:700;cursor:pointer;}",
      ".rv-bar button:hover{background:#fdf3e0;}",
      ".pd-viewas{padding:6px 10px 8px;border-bottom:1px solid var(--border,#e2e8f0);margin-bottom:4px;}",
      ".pd-viewas-label{font-size:10.5px;font-weight:700;letter-spacing:.5px;text-transform:uppercase;",
      "color:var(--muted,#64748b);margin-bottom:5px;}",
      ".pd-viewas button{display:block;width:100%;text-align:left;padding:6px 8px;border-radius:6px;",
      "border:none;background:none;font:inherit;font-size:12.5px;color:var(--text,#0f172a);cursor:pointer;}",
      ".pd-viewas button:hover{background:#eef1f4;}",
      ".pd-viewas button[aria-current=\"true\"]{font-weight:700;background:#eef1f4;}",
      "@media print{.rv-bar{display:none;}}"
    ].join("");
    document.head.appendChild(css);
  }

  function banner(sb, viewing, onExit) {
    var bar = document.createElement("div");
    bar.className = "rv-bar no-print";
    bar.innerHTML = '<span>Viewing as <strong>' + (LABEL[viewing] || viewing) +
      '</strong> — this is what they see, for real. Your Admin rights are off until you exit.</span>';
    var btn = document.createElement("button");
    btn.type = "button";
    btn.textContent = "Exit and go back to Admin";
    btn.addEventListener("click", onExit);
    bar.appendChild(btn);
    document.body.insertBefore(bar, document.body.firstChild);
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
    if (effective !== realRole) banner(sb, effective, clear);
    return profile;
  }

  window.EGRoleView = { mount: mount, LABEL: LABEL };
})();
