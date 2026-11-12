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
      // right so it's not overlapping the menu", then "is it possible to
      // put the Viewing as pill in the blue header under my email address".
      // Yes -- as a full-width item inside #userbox, which wraps it onto a
      // second line of that cluster, right-aligned under the avatar. The
      // header grows by the chip's height; nothing else moves.
      //
      // #userbox is declared on all fourteen pages with slightly different
      // gaps and font sizes but always as a flex row, so wrap is the only
      // thing that has to be added here.
      "#userbox{flex-wrap:wrap;row-gap:6px;}",
      ".rv-chip-row{flex:0 0 100%;display:flex;justify-content:flex-end;}",
      // Loose in the page (no #userbox) it needs its own gutter instead.
      ".rv-chip-row-loose{padding:10px 28px 0;}",
      "@media(max-width:900px){.rv-chip-row-loose{padding:8px 14px 0;}}",
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
    // A second line of #userbox, under the email and the account button
    // (Greg, 11/6/26). It began as the first child of that cluster, which
    // put it on the SAME line as the nav and, once the nav was wide enough,
    // on top of Roster. Wrapping it instead keeps it where it belongs --
    // with the account it describes -- and it cannot collide with anything,
    // because the line is its own.
    var row = document.createElement("div");
    row.className = "rv-chip-row no-print";
    row.appendChild(el);
    var box = document.getElementById("userbox") || document.getElementById("userbox2");
    if (box) {
      box.appendChild(row);
    } else {
      // No account cluster on this page: fall back to a row under the
      // header, which is where it sat before it moved into the header.
      row.className += " rv-chip-row-loose";
      var header = document.querySelector("header");
      if (header && header.parentNode) header.insertAdjacentElement("afterend", row);
      else document.body.insertBefore(row, document.body.firstChild);
    }
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
    { href: "faq_specialists.html", label: "Specialist FAQs" },
    { href: "faq_team_leads.html", label: "Team Lead FAQs" }
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

  // ---------- egWrite: a write that changed nothing is not a success ----------
  // Greg (11/7/26), on six hours of allotment that appeared and vanished:
  // "this is a catastrophe at this point in the rollout and cannot happen
  // again. we need safeguards."
  //
  // PostgREST answers an UPDATE or DELETE that row-level security refused
  // with 200 and an empty body. No error is raised and nothing changed, so
  // code that checks only `error` says "Saved" and the next reload quietly
  // restores the old value. egWrite() asks for the rows the write actually
  // touched and turns "none" into an ordinary error, which means every
  // existing `if (error)` branch in the app catches a refusal with no other
  // change to it.
  //
  // It lives here because this file is the one script all fourteen pages
  // load, and it loads before any of their own code runs. INSERTs are not
  // wrapped anywhere: RLS refuses those with a real 403 that already shows.
  //
  // One caveat worth knowing: .select() re-reads the row under the SELECT
  // policy. Everywhere in this app that policy is broader than the write
  // policy, so a permitted write can always read itself back -- if that ever
  // stops being true somewhere, this would report a false refusal, which is
  // still the safer way to be wrong.
  window.egWrite = async function (query) {
    const { data, error } = await query.select();
    if (error) return { data: null, error: error };
    if (!data || !data.length) {
      var viewingAsOther = !!document.querySelector(".rv-chip");
      return { data: null, error: { message:
        "the database refused it, so nothing was saved. "
        + (viewingAsOther
            ? "You are viewing as another role \u2014 exit that view with the \u00d7 on the amber pill, then try again."
            : "You may not have permission to change this.") } };
    }
    return { data: data, error: null };
  };


  // ---------- Staying signed in ----------
  // Greg (11/8/26): "i was logged in this morning, now i come back and i
  // have to login. what causes this. why don't i stay logged in."
  //
  // The auth log had no answer -- no expiry, no failed refresh, no logout
  // on the server at all -- because the sign-out never got that far. Every
  // page loads by reading its own row out of public.users, and the guard
  // around that read was `if (error || !profile) signOut()`. That treats
  // "we could not ask the database" exactly like "this account has no staff
  // profile", so one dropped request -- a laptop waking before the wi-fi, a
  // slow response, a 5xx -- signed you out. Worse, supabase-js signOut()
  // clears the browser's stored session whether or not the call reaches the
  // server, so you were logged out locally with nothing recorded anywhere.
  //
  // Two fixes, both here so all seventeen pages get the same one:
  //   egShouldSignOut() -- only a positive "no such row" (PGRST116), or a
  //     genuinely dead token, signs anyone out. Anything else keeps the
  //     session and shows the banner below instead.
  //   egSignOut() -- scope "local". supabase-js defaults to "global", which
  //     revokes the session on EVERY device, so signing out on the laptop
  //     silently ended the phone and the desktop too.

  // Sign out of this browser only. Never the other devices.
  window.egSignOut = function (sb) {
    try { return sb.auth.signOut({ scope: "local" }); }
    catch (e) { return sb.auth.signOut(); }   // older supabase-js
  };

  // Is this error the database positively telling us the row is not there,
  // or the session telling us it is over? Those two are worth a sign-out.
  // Everything else -- network, timeout, 5xx, an empty error object -- is
  // "ask again later", and must leave the session alone.
  window.egShouldSignOut = function (err) {
    if (!err) return true;                       // no row, no error: nothing to read
    var code = err.code || "";
    var msg  = (err.message || "") + "";
    if (code === "PGRST116") return true;        // .single() found no row
    if (code === "PGRST301") return true;        // JWT expired / not acceptable
    if (/\bJWT\b|not authenticated|invalid claim/i.test(msg)) return true;
    return false;                                // could not ask -- stay signed in
  };

  // Shown instead of signing someone out when the profile read failed for a
  // reason that is not their account. Deliberately plain and non-dismissable:
  // the page behind it did not finish loading, so there is nothing to go back
  // to except a reload.
  window.egAuthTrouble = function (err) {
    if (document.getElementById("eg-auth-trouble")) return;
    var detail = err && err.message ? String(err.message) : "";
    var bar = document.createElement("div");
    bar.id = "eg-auth-trouble";
    bar.setAttribute("style",
      "position:fixed;inset:0;z-index:99999;display:flex;align-items:center;"
      + "justify-content:center;background:rgba(20,48,77,0.92);padding:24px;"
      + "font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;");
    var card = document.createElement("div");
    card.setAttribute("style",
      "background:#fff;border-radius:12px;max-width:440px;padding:24px 26px;"
      + "box-shadow:0 10px 40px rgba(0,0,0,0.3);color:#1f2937;line-height:1.55;");
    var h = document.createElement("div");
    h.setAttribute("style", "font-weight:700;color:#14304d;font-size:1.05rem;margin-bottom:8px;");
    h.textContent = "Couldn't reach the dashboard";
    var p = document.createElement("p");
    p.setAttribute("style", "margin:0 0 6px;font-size:0.94rem;");
    p.textContent = "You are still signed in — this page just couldn't load your account. "
      + "It is usually the connection. Try again in a moment.";
    var small = document.createElement("p");
    small.setAttribute("style", "margin:0 0 16px;font-size:0.82rem;color:#6b7280;");
    small.textContent = detail;
    var btn = document.createElement("button");
    btn.setAttribute("style",
      "background:#5c7248;color:#fff;border:0;border-radius:6px;padding:9px 18px;"
      + "font-size:0.92rem;font-weight:600;cursor:pointer;");
    btn.textContent = "Try again";
    btn.onclick = function () { location.reload(); };
    card.appendChild(h); card.appendChild(p);
    if (detail) card.appendChild(small);
    card.appendChild(btn);
    bar.appendChild(card);
    (document.body || document.documentElement).appendChild(bar);
  };

  window.EGRoleView = { mount: mount, LABEL: LABEL, helpLinks: helpLinks };
})();
