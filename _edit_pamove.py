# -*- coding: utf-8 -*-
import io
P = "client_applications.html"
s = io.open(P, encoding="utf-8").read()

def sub_once(old, new, what):
    global s
    assert s.count(old) == 1, "%s x%d" % (what, s.count(old))
    s = s.replace(old, new, 1)

# ========== 1. the button lives with the approval, not with the accept ==========
sub_once('''        <div class="approval-note" id="approval-note">${note}</div>
      </div>`;''',
'''        <div class="approval-note" id="approval-note">${note}</div>
        ${approved ? `<div class="approval-actions">
          <button type="button" class="btn-secondary btn-sm" id="pa-notice-btn">Send the approval notice to the Program Administrator</button>
        </div>` : ""}
      </div>`;''',
"button in gate")

sub_once('''  .approval-note { font-size: 12.5px; color: var(--muted); margin: 6px 0 0 28px; }
''', '''  .approval-note { font-size: 12.5px; color: var(--muted); margin: 6px 0 0 28px; }
  .approval-actions { margin: 10px 0 0 28px; }
  .approval-actions button { padding: 6px 12px; font-size: 12.5px; }
''', "button css")

# ========== 2. accept goes back to redirecting; no letter here ==========
sub_once('''    // ---------- hand Rita the letter to the Program Administrator ----------
    // Chris's order of operations (9/26/26, via Greg): the Program hears once
    // there is an engagement and a Team Lead. Greg then supplied the letter
    // Rita actually sends (9/28/26) -- signed "Rita Benson, Administrator",
    // with the NCEG address block, and asking the PA to send the acceptance
    // notification on to the company.
    //
    // WHICH IS WHY THIS IS A COMPOSER AND NOT AN AUTOMATIC SEND. An email
    // from the dashboard leaves as noreply@send.economicgardening.org: it
    // cannot carry her signature, a reply to it goes nowhere, and a request
    // to go and do something reads oddly from a machine. So the app writes
    // the letter and hands it to her mail client -- out from her address,
    // into her Sent folder, and editable first. Same pattern as the
    // engagement Welcome Email, for the same reasons.
    //
    // It also means NOT redirecting to the Engagements page the moment the
    // engagement exists, which is what this did until today. There is a step
    // left, so the page stays put and shows it.
    btn.disabled = true;
    btn.textContent = "Engagement created";
    showBanner(`Client created at ${slug}.egdashboardbuilder.com.`, "success");
    renderPaLetter(appId, clientId);
  }''',
'''    btn.disabled = false;
    btn.textContent = "Accept and Create Engagement";
    showBanner(`Client created at ${slug}.egdashboardbuilder.com.`, "success");
    location.href = "index.html";
  }''',
"accept tail")

# ========== 3. the composer is opened from the approval, and knows why ==========
sub_once('''  function renderPaLetter(appId, clientId) {
    const a = allApplications.find((x) => x.id === appId);
    if (!a) return;''',
'''  // Opened by the button on the approval box, NOT by accepting.
  //
  // Greg (9/28/26) caught this: "he or Rita can approve the application. That
  // sends a notice to the PA that NCEG has approved the application (no TL
  // assigned yet). PA then sends acceptance letter to the applicant and cc's
  // Rita. then rita adds the TL and hours."
  //
  // So the Program hears at approval, and their reply is what starts the
  // Team Lead assignment -- the letter cannot wait for the accept, because
  // the accept is downstream of it. It had been sitting on the accept since
  // 9/28/26 morning, which would have deadlocked the two halves of the
  // process against each other: Rita waiting for the PA, the PA waiting for
  // a letter that only arrives once Rita has finished.
  //
  // The button stays on the box rather than appearing once, so a closed tab
  // or a second thought is no reason to retype it.
  function renderPaLetter(appId) {
    const a = allApplications.find((x) => x.id === appId);
    if (!a) return;
    const existing = document.getElementById("pa-letter");
    if (existing) existing.remove();''',
"composer signature")

sub_once('''      <h4>Next step — tell the Program Administrator</h4>
      <p class="desc">${pas.length''',
'''      <h4>Next step — tell the Program Administrator that NCEG has approved this</h4>
      <p class="desc">${pas.length''',
"composer heading")

# The letter's own closing line already asks the PA to send the acceptance
# notification, which is exactly right at this point in the sequence.
sub_once('''        <a class="btn-secondary" id="pa-done" href="index.html" style="text-decoration:none; display:inline-block;">Go to Engagements →</a>''',
'''        <button type="button" class="btn-secondary" id="pa-close">Close</button>''',
"composer actions")

sub_once('''    $("pa-copy").addEventListener("click", async () => {''',
'''    $("pa-close").addEventListener("click", () => { const el = document.getElementById("pa-letter"); if (el) el.remove(); });

    $("pa-copy").addEventListener("click", async () => {''',
"close wiring")

# ========== 4. wire the button ==========
sub_once('''      const ruralBox = $("accept-rural");''',
'''      const paBtn = $("pa-notice-btn");
      if (paBtn) paBtn.addEventListener("click", () => renderPaLetter(a.id));

      const ruralBox = $("accept-rural");''',
"button wiring")

io.open(P, "w", encoding="utf-8").write(s)
print("ok")
