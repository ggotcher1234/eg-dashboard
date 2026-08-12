// supabase/functions/eg-dashboard-ai/index.ts
//
// Ask AI backend for the EG Dashboard. Browser -> this function -> Claude API.
// The Claude API key never touches the browser; it lives only as the
// ANTHROPIC_API_KEY secret on this function (set yourself via
// `supabase secrets set ANTHROPIC_API_KEY=...` or the Supabase dashboard's
// Edge Functions -> Secrets page -- never pasted into chat or committed to
// source).
//
// Auth model:
//   - Every caller must send a real Supabase user session JWT (not just the
//     anon/publishable key) in the Authorization header, so this function
//     knows WHO is asking. The front-end passes `session.access_token` from
//     `sb.auth.getSession()`, not the anon key.
//   - Only users whose role is "super_admin" (labeled "Admin" in the UI) get
//     answers built from live Supabase data. Everyone else gets a
//     navigation/how-to style answer with zero data queries run, so there's
//     no path for a non-admin to fish sensitive figures out of the model.
//
// Deploy: paste this into the eg-dashboard-ai function's "Code" tab in the
// Supabase dashboard and hit Deploy, OR if you set up the Supabase CLI
// locally, run `supabase functions deploy eg-dashboard-ai` from the
// eg-dashboard repo root (this file lives at
// supabase/functions/eg-dashboard-ai/index.ts).
//
// Required secret (set this yourself -- see instructions above):
//   ANTHROPIC_API_KEY = sk-ant-...
//
// SUPABASE_URL is injected automatically by Supabase into every Edge
// Function's environment -- nothing to set for that.
//
// This function deliberately does NOT use SUPABASE_ANON_KEY or
// SUPABASE_SERVICE_ROLE_KEY / SUPABASE_SECRET_KEYS. This project is on
// Supabase's newer publishable/secret key system (sb_publishable_...,
// sb_secret_...), and those legacy env vars are marked Deprecated for
// projects like this one -- they may be empty. Instead:
//   - The publishable key comes from the incoming request's own `apikey`
//     header (the browser already sends it, same as every other call this
//     app makes to Supabase).
//   - There is no service-role client anywhere in this function. Admin data
//     queries run through the SAME forwarded-user-JWT client used to
//     identify the caller, exactly like every admin page in this app
//     already works -- they rely on this project's RLS policies already
//     granting Admins (super_admin) broad read access, not on a
//     bypass-everything secret key. That keeps this function no more
//     privileged than the app's own front-end already is.
//
// Also: in this function's Settings tab, turn OFF "Verify JWT with legacy
// secret." That platform-level check only confirms the caller sent *some*
// valid Supabase-issued token (the publishable key satisfies it) -- it does
// not identify who is asking. This function does its own, stronger check
// below (a real user session, looked up against the users table), which is
// what the Supabase UI itself recommends when you have custom auth logic.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;

// Update this if Anthropic renames/retires the model slug.
const CLAUDE_MODEL = "claude-sonnet-5";

const ROLE_LABELS: Record<string, string> = {
  consultant: "Specialist",
  team_lead: "Team Lead",
  super_admin: "Admin",
};

// Short description of each page, used so non-admins (and admins asking
// something with no matching data) get a useful "how do I..." answer
// instead of an empty one. Keys match the `pageKey` the front-end sends.
const PAGE_HELP: Record<string, string> = {
  dashboard:
    "The main EG Dashboard home page. Shows engagement status counts (Pending, Accepted, In Progress, On Hold, Closed), admin tool shortcuts (Engagement Applications, Programs, EG Team, Invoicing Report), and a searchable list of recent/all engagements.",
  applications:
    "The Engagement Applications page, where new client applications are reviewed and accepted or declined, and where a 5-step wizard is used to submit a brand-new application.",
  programs:
    "The Programs page (Econ Dev Partners), listing partner organizations, their contacts, and which engagements are linked to each program.",
  team:
    "The EG Team directory, listing every team member, their role (Specialist / Team Lead / Admin), contact info, and specialties.",
  invoicing:
    "The Invoicing Report, used by the bookkeeper/admin to review hours by specialist, budget alerts, and payroll (Month-to-Date and Year-to-Date) for a selected month.",
  workspace:
    "The Engagement Workspace for a single engagement -- quick links to its Assignments & Hours, Dashboard Files & Data, drafting a client update email, and the client-facing dashboard.",
  assignments:
    "The Assignments & Hours page for a single engagement -- shows each specialist's role, hours allotted vs. spent, and lets a Team Lead or Admin log hours or adjust assignments.",
  profile:
    "The Dashboard Edit page for a single engagement -- edits everything that appears on the client-facing dashboard: company info, contacts, competitors, top customers, resource vault documents, and project next steps.",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    if (!ANTHROPIC_API_KEY) {
      return jsonResponse(
        { error: "Server is missing ANTHROPIC_API_KEY. Set it with `supabase secrets set ANTHROPIC_API_KEY=...` or in the dashboard's Edge Functions secrets page." },
        500,
      );
    }

    const authHeader = req.headers.get("Authorization") || "";
    if (!authHeader.startsWith("Bearer ")) {
      return jsonResponse({ error: "Missing user session." }, 401);
    }

    // The browser sends the project's publishable key as `apikey` on every
    // Supabase call, same as this app's front-end pages already do -- reuse
    // it here rather than depending on a possibly-empty legacy env var.
    const publishableKey = req.headers.get("apikey") || req.headers.get("Apikey") || "";
    if (!publishableKey) {
      return jsonResponse({ error: "Missing apikey header." }, 401);
    }

    const body = await req.json().catch(() => null);
    const question = body?.question;
    const pageKey = body?.pageKey as string | undefined;
    const pageContext = body?.pageContext as string | undefined;
    const clientId = body?.clientId as string | undefined;

    if (!question || typeof question !== "string") {
      return jsonResponse({ error: "Missing question." }, 400);
    }

    // Identify the caller from their OWN session JWT (not just the
    // publishable key) -- this is what actually tells us who is asking.
    const userClient = createClient(SUPABASE_URL, publishableKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: userErr } = await userClient.auth.getUser();
    if (userErr || !user) {
      return jsonResponse({ error: "Could not verify your session -- try signing in again." }, 401);
    }

    const { data: profile } = await userClient
      .from("users")
      .select("id, full_name, role")
      .eq("id", user.id)
      .single();

    const role = profile?.role || "consultant";
    const isAdmin = role === "super_admin";

    // Same forwarded-JWT client used above -- if this project's RLS grants
    // Admins broad read access (it must, since the app's own admin pages
    // already query these tables this way), these queries just work. No
    // service-role / secret key is used anywhere in this function.
    let dataContext = "";
    if (isAdmin) {
      dataContext = await buildAdminContext(userClient, pageKey, clientId);
    }

    const systemPrompt = buildSystemPrompt({
      userName: profile?.full_name || "there",
      roleLabel: ROLE_LABELS[role] || role,
      isAdmin,
      pageKey,
      pageContext,
      dataContext,
    });

    const claudeRes = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: CLAUDE_MODEL,
        max_tokens: 600,
        system: systemPrompt,
        messages: [{ role: "user", content: question }],
      }),
    });

    if (!claudeRes.ok) {
      const errText = await claudeRes.text();
      console.error("Claude API error:", claudeRes.status, errText);
      return jsonResponse({ error: "The AI service had a problem answering that. Try again in a moment." }, 502);
    }

    const claudeData = await claudeRes.json();
    const answer = claudeData?.content?.[0]?.text || "Sorry, I couldn't come up with an answer to that.";

    return jsonResponse({ answer, isAdmin });
  } catch (err) {
    console.error("eg-dashboard-ai error:", err);
    return jsonResponse({ error: "Something went wrong answering that question." }, 500);
  }
});

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function buildSystemPrompt(opts: {
  userName: string;
  roleLabel: string;
  isAdmin: boolean;
  pageKey?: string;
  pageContext?: string;
  dataContext: string;
}) {
  const pageHelp =
    (opts.pageKey && PAGE_HELP[opts.pageKey]) ||
    "A page inside the EG Dashboard app, an internal tool EG Group uses to manage economic gardening engagements with client companies.";

  let prompt = `You are "Ask AI," a helpful assistant embedded in the EG Dashboard app, an internal tool EG Group's staff use to manage economic gardening engagements.

You're answering a question from ${opts.userName}, who is signed in as a ${opts.roleLabel}. They are currently on: ${opts.pageContext || opts.pageKey || "an EG Dashboard page"}.

About this page: ${pageHelp}

Keep answers short (2-5 sentences, or a short list if that's clearer), specific, and friendly. Plain text with occasional **bold** for key terms or numbers -- no headers.`;

  if (opts.isAdmin && opts.dataContext) {
    prompt += `

You have permission to answer using the live data below, because this user is an Admin. Only use the facts given here -- never invent numbers. If the data below doesn't answer their question, say so and suggest where in the app they could look.

LIVE DATA:
${opts.dataContext}`;
  } else if (opts.isAdmin) {
    prompt += `

No live data was available for this page or question. Answer generally, based on how the app works, and suggest what to check on-screen.`;
  } else {
    prompt += `

This user is NOT an Admin, so you have not been given any live data for this request -- do not claim to know specific figures (hours, payroll, budgets, counts, other engagements' details, etc.). If they ask for something like that, tell them to check the relevant section on this page, or ask an Admin. Focus on explaining how to use the app, where to find things, and how to phrase useful questions.`;
  }

  return prompt;
}

// Builds a compact, plain-text summary of live data relevant to the page the
// admin is on. Keep each branch cheap -- a handful of small queries, not a
// full data dump. Column/table names here match what the front-end pages
// already query (clients, client_assignments, time_entries,
// client_applications, organization_settings, users, client_next_steps).
async function buildAdminContext(
  userClient: ReturnType<typeof createClient>,
  pageKey?: string,
  clientId?: string,
): Promise<string> {
  try {
    switch (pageKey) {
      case "dashboard": {
        const [{ data: clients }, { count: pendingCount }] = await Promise.all([
          userClient.from("clients").select("project_status"),
          userClient.from("client_applications").select("id", { count: "exact", head: true }).eq("status", "pending"),
        ]);
        const counts: Record<string, number> = {};
        for (const c of clients || []) counts[(c as any).project_status] = (counts[(c as any).project_status] || 0) + 1;
        return `Pending applications: ${pendingCount ?? 0}
Engagements by status: ${Object.entries(counts).map(([k, v]) => `${k}: ${v}`).join(", ") || "none"}`;
      }

      case "applications": {
        const { data: apps } = await userClient
          .from("client_applications")
          .select("company_name, status, submitted_at")
          .eq("status", "pending")
          .order("submitted_at", { ascending: false })
          .limit(10);
        if (!apps?.length) return "No pending applications right now.";
        return (
          "Pending applications:\n" +
          apps.map((a: any) => `- ${a.company_name} (submitted ${a.submitted_at?.slice(0, 10) || "unknown date"})`).join("\n")
        );
      }

      case "programs": {
        const { data: partners } = await userClient.from("econ_dev_companies").select("id, name");
        return `Total programs/partners: ${partners?.length ?? 0}`;
      }

      case "team": {
        const { data: users } = await userClient.from("users").select("role");
        const counts: Record<string, number> = {};
        for (const u of users || []) counts[(u as any).role] = (counts[(u as any).role] || 0) + 1;
        return `Team headcount by role: ${
          Object.entries(counts).map(([k, v]) => `${ROLE_LABELS[k] || k}: ${v}`).join(", ") || "none"
        }`;
      }

      case "invoicing": {
        const now = new Date();
        const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).toISOString().slice(0, 10);
        const [{ data: entries }, { data: orgSettings }] = await Promise.all([
          userClient.from("time_entries").select("hours, entry_date").gte("entry_date", monthStart),
          userClient.from("organization_settings").select("hourly_rate").limit(1).maybeSingle(),
        ]);
        const totalHours = (entries || []).reduce((s: number, e: any) => s + Number(e.hours || 0), 0);
        const rate = (orgSettings as any)?.hourly_rate;
        const payroll = rate ? (totalHours * Number(rate)).toFixed(2) : null;
        return `Hours logged this month so far: ${totalHours.toFixed(1)}${
          payroll ? `\nEstimated payroll this month so far (at $${rate}/hr): $${payroll}` : ""
        }`;
      }

      case "workspace":
      case "assignments":
      case "profile": {
        if (!clientId) return "";
        const [{ data: client }, { data: assignments }, { data: nextSteps }] = await Promise.all([
          userClient.from("clients").select("name, project_status, budget_hours_available, updated_at").eq("id", clientId).single(),
          userClient.from("client_assignments").select("specialty_type, hours_allotted, users(full_name, role)").eq("client_id", clientId),
          userClient.from("client_next_steps").select("description").eq("client_id", clientId).eq("completed", false).order("sort_order").limit(1),
        ]);
        if (!client) return "";
        const totalAllotted = (assignments || []).reduce((s: number, a: any) => s + Number(a.hours_allotted || 0), 0);
        const teamList = (assignments || [])
          .filter((a: any) => a.users?.full_name)
          .map((a: any) => `${a.users.full_name} (${a.specialty_type})`)
          .join(", ");
        return `Engagement: ${(client as any).name}
Status: ${(client as any).project_status}
Hours allotted total: ${totalAllotted}${(client as any).budget_hours_available != null ? ` of ${(client as any).budget_hours_available} budgeted` : ""}
Team: ${teamList || "none assigned"}
Next step: ${nextSteps?.[0] ? (nextSteps[0] as any).description : "none set"}
Last updated: ${(client as any).updated_at?.slice(0, 10) || "unknown"}`;
      }

      default:
        return "";
    }
  } catch (err) {
    console.error("buildAdminContext error:", err);
    return "";
  }
}
