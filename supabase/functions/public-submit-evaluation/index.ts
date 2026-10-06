// public-submit-evaluation
//
// The Edge Function a client's Evaluation Sheet link submits to. There is no
// Supabase session behind that page -- a CEO opens the link, fills it in,
// hits Submit -- so this function is the entire write path: validate, then
// write with the service-role client (never the anon key).
//
// 10/6/26, v4: this slug had been running the SOURCE OF
// public-submit-application since 8/30 (wrong file pasted into the dashboard),
// so every submission answered 400 "Missing program." and
// client_evaluation_responses stood at zero rows. See 147.
//
// 10/6/26, v5, Greg: "we need to make sure the admins are copied when an
// Evaluation Sheet is submitted. not just a bell notification... I'd like to
// get an email saying it was submitted, it is attached to the email and
// available to download on the Clippard Dashboard." Recipients confirmed as
// the engagement's Team Lead plus all admins.
//
// THE ORDER MATTERS. The response is inserted and committed FIRST, and only
// then are the PDF, the upload and the email attempted, each inside its own
// guard. A CEO's answers must never be lost because Resend was down or a
// font failed to embed -- that is the whole lesson of the bug above. Anything
// that fails here comes back as a `warning` on an otherwise successful
// response, and the bell notification (078's trigger) fires regardless.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { PDFDocument, StandardFonts, rgb } from "https://esm.sh/pdf-lib@1.17.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const MAX_TEXT = 5000;
function clampText(v: unknown): string | null {
  if (v === undefined || v === null) return null;
  const s = String(v).trim();
  if (!s) return null;
  return s.slice(0, MAX_TEXT);
}

// respondent_date is a DATE column and the page's input is type="date", so a
// real submission sends YYYY-MM-DD. Anything else is dropped rather than
// allowed to fail the insert and read, to a CEO, as the form being broken.
function clampDate(v: unknown): string | null {
  const s = clampText(v);
  if (!s) return null;
  return /^\d{4}-\d{2}-\d{2}$/.test(s) ? s : null;
}

function escapeHtml(str: string) {
  return String(str)
    .split("&").join("&amp;")
    .split("<").join("&lt;")
    .split(">").join("&gt;")
    .split('"').join("&quot;");
}

// btoa() on a long binary string blows the argument limit, so chunk it.
function bytesToBase64(bytes: Uint8Array): string {
  let bin = "";
  const CHUNK = 0x8000;
  for (let i = 0; i < bytes.length; i += CHUNK) {
    bin += String.fromCharCode(...bytes.subarray(i, i + CHUNK));
  }
  return btoa(bin);
}

// ---------------------------------------------------------------- THE PDF
const NAVY  = rgb(0.078, 0.188, 0.302);
const GREEN = rgb(0.129, 0.286, 0.149);
const SAGE  = rgb(0.361, 0.447, 0.282);
const GREY  = rgb(0.38, 0.42, 0.47);
const LINE  = rgb(0.85, 0.87, 0.85);
const RATING_LABEL: Record<string, string> = { very: "Very Useful", partial: "Partially Useful", not: "Not Useful" };

async function buildEvaluationPdf(r: any): Promise<Uint8Array> {
  const doc = await PDFDocument.create();
  const reg  = await doc.embedFont(StandardFonts.Helvetica);
  const bold = await doc.embedFont(StandardFonts.HelveticaBold);
  const obl  = await doc.embedFont(StandardFonts.HelveticaOblique);

  const W = 612, H = 792, M = 54;
  let page = doc.addPage([W, H]);
  let y = H - M;

  const newPage = () => { page = doc.addPage([W, H]); y = H - M; };
  const room = (n: number) => { if (y - n < M) newPage(); };

  const wrap = (text: unknown, font: any, size: number, maxW: number) => {
    const out: string[] = [];
    String(text ?? "").split(/\r?\n/).forEach((para) => {
      let line = "";
      para.split(/\s+/).filter(Boolean).forEach((word) => {
        const next = line ? line + " " + word : word;
        if (font.widthOfTextAtSize(next, size) <= maxW) { line = next; }
        else { if (line) out.push(line); line = word; }
      });
      out.push(line);
    });
    return out.length ? out : [""];
  };

  const text = (s: unknown, o: any = {}) => {
    const font = o.font ?? reg, size = o.size ?? 10, color = o.color ?? rgb(0.1, 0.1, 0.1);
    const x = o.x ?? M, maxW = o.maxW ?? (W - M * 2), lead = o.lead ?? 1.38;
    wrap(s, font, size, maxW).forEach((line) => {
      room(size * lead);
      page.drawText(line, { x, y: y - size, size, font, color });
      y -= size * lead;
    });
  };

  const gap = (n: number) => { y -= n; };
  const rule = () => { room(10); page.drawLine({ start: { x: M, y }, end: { x: W - M, y }, thickness: 0.75, color: LINE }); y -= 12; };
  const heading = (s: string) => { room(26); gap(6); text(s, { font: bold, size: 11.5, color: GREEN }); gap(3); };

  page.drawRectangle({ x: 0, y: H - 86, width: W, height: 86, color: NAVY });
  page.drawText("NATIONAL CENTER FOR ECONOMIC GARDENING", { x: M, y: H - 38, size: 9, font: bold, color: rgb(0.78, 0.84, 0.89) });
  page.drawText("Evaluation Sheet", { x: M, y: H - 64, size: 19, font: bold, color: rgb(1, 1, 1) });
  y = H - 108;

  text(r.company_name || "", { font: bold, size: 15, color: NAVY });
  gap(2);
  const meta = [
    r.sponsor_name ? "Program: " + r.sponsor_name : null,
    r.respondent_name ? "Completed by: " + r.respondent_name : null,
    r.respondent_date ? "Dated: " + r.respondent_date : null,
    r.submitted_at ? "Submitted: " + new Date(r.submitted_at).toLocaleDateString("en-US") : null,
  ].filter(Boolean).join("   •   ");
  text(meta, { size: 9.5, color: GREY });
  gap(8); rule();

  heading("How useful was the research in answering the questions in the controlling document?");
  const ratings = Array.isArray(r.question_ratings) ? r.question_ratings : [];
  ratings.forEach((q: any, i: number) => {
    room(30);
    // The rating belongs beside the FIRST line of its question. Level with
    // the last line, on a four-line question, it reads as belonging to the
    // row below.
    const topY = y, topPage = page;
    text(String(i + 1) + ". " + String(q.question || "").replace(/^\s*\d+\.\s*/, ""), { size: 9.5, maxW: W - M * 2 - 110 });
    topPage.drawText(RATING_LABEL[q.rating] || "—", {
      x: W - M - 100, y: topY - 9.5, size: 9.5, font: bold,
      color: q.rating === "very" ? SAGE : q.rating === "partial" ? rgb(0.66, 0.45, 0.06) : GREY,
    });
    gap(6);
  });
  gap(2);
  const v = r.very_useful_count ?? 0, pc = r.partially_useful_count ?? 0, n = r.not_useful_count ?? 0;
  // Runs of spaces collapse in wrap(), so separators must be real characters.
  text(`Very Useful: ${v}  •  Partially Useful: ${pc}  •  Not Useful: ${n}  •  Weighted Score: ${r.weighted_score ?? 0} / ${r.weighted_max ?? 0}`,
       { font: bold, size: 10, color: NAVY });
  if (r.q1_explain) {
    gap(4);
    text("Explanation of any Partially / Not Useful answers:", { font: bold, size: 9.5, color: GREY });
    text(r.q1_explain, { size: 10 });
  }
  gap(6); rule();

  heading("Were you adequately prepared for the engagement?");
  text(r.prepared === "yes" ? "Yes" : r.prepared === "no" ? "No" : "—", { size: 10 });
  if (r.prepared_explain) text(r.prepared_explain, { size: 10 });
  gap(6); rule();

  heading("What could we have done better or differently?");
  text(r.improvement_suggestions || "No answer given.", { size: 10, font: r.improvement_suggestions ? reg : obl });
  gap(6); rule();

  heading("How likely are you to recommend this program? (1–10)");
  text(r.nps_score === null || r.nps_score === undefined ? "—" : String(r.nps_score), { font: bold, size: 13, color: NAVY });
  if (r.nps_explain) text(r.nps_explain, { size: 10 });
  gap(6); rule();

  heading("Other CEOs or companies who might benefit");
  const refs = (Array.isArray(r.referrals) ? r.referrals : []).filter((x: any) => x && (x.name || x.company || x.contact));
  if (!refs.length) text("None given.", { size: 10, font: obl, color: GREY });
  else refs.forEach((x: any) => text("• " + [x.name, x.company, x.contact].filter(Boolean).join(" — "), { size: 10 }));

  if (r.testimonial) { gap(6); rule(); heading("Testimonial"); text(r.testimonial, { size: 10, font: obl }); }

  const pages = doc.getPages();
  pages.forEach((pg: any, i: number) => {
    pg.drawText(`National Center for Economic Gardening  ·  Evaluation Sheet  ·  page ${i + 1} of ${pages.length}`,
      { x: M, y: 30, size: 8, font: reg, color: GREY });
  });
  return await doc.save();
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);

  try {
    const body = await req.json().catch(() => ({}));
    const clientId = (body.clientId || "").trim();
    const data = body.data || {};

    if (!clientId) return jsonResponse({ error: "Missing client." }, 400);

    const questionRatings = Array.isArray(data.questionRatings) ? data.questionRatings : [];
    if (!questionRatings.length) {
      return jsonResponse({ error: "Please answer at least one research question before submitting." }, 400);
    }
    const cleanRatings = questionRatings
      .map((r: any) => ({
        question: clampText(r && r.question) || "",
        rating: ["very", "partial", "not"].includes(r && r.rating) ? r.rating : null,
      }))
      .filter((r: any) => r.question || r.rating);

    const cleanReferrals = (Array.isArray(data.referrals) ? data.referrals : [])
      .map((r: any) => ({ name: clampText(r && r.name), company: clampText(r && r.company), contact: clampText(r && r.contact) }))
      .filter((r: any) => r.name || r.company || r.contact);

    const npsScoreRaw = data.npsScore;
    const npsScore = Number.isFinite(Number(npsScoreRaw)) && npsScoreRaw !== null && npsScoreRaw !== ""
      ? Math.max(1, Math.min(10, Math.round(Number(npsScoreRaw)))) : null;

    const countInt = (v: unknown) => { const n = Number(v); return Number.isFinite(n) && n >= 0 ? Math.round(n) : 0; };

    const adminClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { autoRefreshToken: false, persistSession: false } },
    );

    const { data: client, error: clientErr } = await adminClient
      .from("clients").select("id, name").eq("id", clientId).maybeSingle();
    if (clientErr) return jsonResponse({ error: clientErr.message }, 400);
    if (!client) return jsonResponse({ error: "Unknown client link. Please double-check the URL you were given." }, 400);

    const row = {
      client_id: clientId,
      respondent_name: clampText(data.respondentName),
      respondent_date: clampDate(data.respondentDate),
      company_name: clampText(data.companyName),
      sponsor_name: clampText(data.sponsorName),
      question_ratings: cleanRatings,
      q1_explain: clampText(data.q1Explain),
      prepared: ["yes", "no"].includes(data.prepared) ? data.prepared : null,
      prepared_explain: clampText(data.preparedExplain),
      improvement_suggestions: clampText(data.improvementSuggestions),
      nps_score: npsScore,
      nps_explain: clampText(data.npsExplain),
      referrals: cleanReferrals,
      testimonial: clampText(data.testimonial),
      very_useful_count: countInt(data.veryUsefulCount),
      partially_useful_count: countInt(data.partiallyUsefulCount),
      not_useful_count: countInt(data.notUsefulCount),
      weighted_score: countInt(data.weightedScore),
      weighted_max: countInt(data.weightedMax),
    };

    // ---- THE ONLY STEP THAT MAY FAIL THE REQUEST ----
    const { data: inserted, error: insertErr } = await adminClient
      .from("client_evaluation_responses").insert(row).select("id, submitted_at").single();
    if (insertErr) return jsonResponse({ error: insertErr.message }, 400);

    // ---- Everything below is best-effort. The answers are already saved. ----
    let warning: string | null = null;
    try {
      const full = { ...row, submitted_at: inserted.submitted_at };
      const pdfBytes = await buildEvaluationPdf(full);
      const safeCompany = String(client.name || "Client").replace(/[^a-zA-Z0-9._-]/g, "_").slice(0, 60);
      const fileName = `NCEG-Evaluation-${safeCompany}.pdf`;
      const path = `submitted/${clientId}/${inserted.id}-${fileName}`;

      const { error: upErr } = await adminClient.storage
        .from("client-evaluations")
        .upload(path, pdfBytes, { contentType: "application/pdf", upsert: true });
      if (upErr) throw new Error("Upload failed: " + upErr.message);

      const { data: pub } = adminClient.storage.from("client-evaluations").getPublicUrl(path);
      const pdfUrl = pub.publicUrl;
      await adminClient.from("client_evaluation_responses").update({ pdf_url: pdfUrl }).eq("id", inserted.id);

      // Recipients: every active Admin, plus this engagement's Team Lead.
      // Read from the database rather than hardcoded -- the four Workflow
      // Documents composers still carry a hardcoded pair, and this must not
      // inherit that.
      const { data: admins } = await adminClient
        .from("users").select("email").eq("role", "super_admin").is("archived_at", null);
      const { data: leads } = await adminClient
        .from("client_assignments").select("users(email, archived_at)")
        .eq("client_id", clientId).eq("is_team_lead", true);

      const to = Array.from(new Set([
        ...(admins || []).map((u: any) => u.email),
        ...(leads || []).map((a: any) => a.users && !a.users.archived_at ? a.users.email : null),
      ].filter(Boolean).map((e: string) => e.toLowerCase())));
      if (!to.length) throw new Error("No admin or team lead address to send to.");

      const resendKey = Deno.env.get("RESEND_API_KEY");
      if (!resendKey) throw new Error("RESEND_API_KEY secret is not set.");

      const who = row.respondent_name ? escapeHtml(row.respondent_name) : "The client";
      const res = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { Authorization: `Bearer ${resendKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          // The verified domain. onboarding@resend.dev is Resend's shared
          // sandbox sender and can ONLY reach the account owner -- it 403s
          // the whole send the moment another recipient is on it, which is
          // exactly what the first test of this did. Every other function
          // in this project already sends from the verified domain.
          from: "EG Dashboard <noreply@send.economicgardening.org>",
          reply_to: "egdashboard@economicgardening.org",
          to,
          subject: `Evaluation Sheet submitted: ${client.name}`,
          html: `
            <p><strong>${escapeHtml(client.name)}</strong> has submitted their Evaluation Sheet.</p>
            <p>
              <strong>Completed by:</strong> ${who}<br/>
              <strong>Ratings:</strong> ${row.very_useful_count} Very Useful, ${row.partially_useful_count} Partially Useful, ${row.not_useful_count} Not Useful<br/>
              <strong>Weighted score:</strong> ${row.weighted_score} / ${row.weighted_max}<br/>
              <strong>Would recommend (1–10):</strong> ${row.nps_score ?? "—"}
            </p>
            <p>The completed sheet is attached, and it is on the client's dashboard under Evaluation Sheet.</p>
            <p style="color:#64748b;font-size:12px;">Submitting the evaluation closes the engagement.</p>
          `,
          attachments: [{ filename: fileName, content: bytesToBase64(pdfBytes) }],
        }),
      });
      if (!res.ok) throw new Error(`Resend returned ${res.status}: ${await res.text().catch(() => "")}`);
    } catch (e) {
      console.error("Evaluation PDF/email step failed:", e instanceof Error ? e.message : e);
      warning = "Your evaluation was saved. The copy emailed to your EG team didn't go out — they can still see your answers on the dashboard.";
    }

    return jsonResponse({ ok: true, warning });
  } catch (e) {
    return jsonResponse({ error: e instanceof Error ? e.message : "Unexpected error." }, 500);
  }
});
