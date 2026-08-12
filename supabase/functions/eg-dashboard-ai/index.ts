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
//     publishable key) in the Authorization header, so this function knows
//     WHO is asking. The front-end passes `session.access_token` from
//     `sb.auth.getSession()`.
//   - Only users whose role is "super_admin" (labeled "Admin" in the UI) get
//     tool access to live Supabase data. Everyone else gets a
//     navigation/how-to style answer with zero data queries run, so there's
//     no path for a non-admin to fish sensitive figures out of the model.
//
// How Admins get "any info, any page":
//   Rather than pre-picking a fixed handful of facts per page (which meant
//   a simple question like "what applications are pending" on the home
//   page couldn't surface an applicant's name), this function gives Claude
//   a small set of read-only Supabase query TOOLS (list_engagements,
//   get_engagement_detail, list_applications, list_team,
//   get_hours_and_payroll, list_programs) and lets it call whichever ones
//   it needs, in a loop, until it has enough to answer. This covers
//   questions about any engagement/application/specialist/program/month,
//   not just the page the user happens to be on.
//
//   Every tool call runs through the SAME forwarded-user-JWT Supabase
//   client used to identify the caller -- there is no service-role /
//   secret-key client anywhere in this function. Tool access is only ever
//   handed to Claude after the caller is confirmed to be an Admin, and
//   every query still passes through this project's RLS, so this function
//   is never more privileged than the app's own front-end already is.
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
// Function's environment -- nothing to set for that. This project is on
// Supabase's newer publishable/secret key system, so the legacy
// SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY env vars are deliberately
// not used here (see note below); the publishable key instead comes from
// the incoming request's own `apikey` header, same as every front-end page
// already sends.
//
// Also: in this function's Settings tab, turn OFF "Verify JWT with legacy
// secret." That platform-level check only confirms the caller sent *some*
// valid Supabase-issued token (the publishable key satisfies it) -- it does
// not identify who is asking. This function does its own, stronger check
// below (a real user session, looked up against the users table), which is
// what the Supabase UI itself recommends when you have custom auth logic.

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;

// Update this if Anthropic renames/retires the model slug.
const CLAUDE_MODEL = "claude-sonnet-5";
const MAX_TOOL_ROUNDS = 5;

const ROLE_LABELS: Record<string, string> = {
  consultant: "Specialist",
  team_lead: "Team Lead",
  super_admin: "Admin",
};

// Short description of each page, used purely as orientation context (e.g.
// "the user is on the Invoicing Report") and for non-admins, who get no
// tool access at all -- just a how-to-use-this-page answer.
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

// ---------- Tool definitions (Anthropic tool-use schema) ----------
// A small, fixed set of read-only report queries -- not raw SQL. Claude
// picks which of these to call (and with what filters) based on the
// question; we execute them through the RLS-scoped, forwarded-JWT client
// and hand the result back.
const ADMIN_TOOLS = [
  {
    name: "list_engagements",
    description:
      "List engagements (client companies), optionally filtered by project status or a name search. Use for questions like 'which engagements are on hold' or 'how many engagements are in progress'.",
    input_schema: {
      type: "object",
      properties: {
        project_status: {
          type: "string",
          enum: ["accepted", "in_progress", "on_hold", "closed"],
          description: "Filter to one status. Omit to get all.",
        },
        search: { type: "string", description: "Case-insensitive substring match on engagement name." },
      },
    },
  },
  {
    name: "get_engagement_detail",
    description:
      "Get full detail for ONE specific engagement: status, hours budget/used, team assignments, open next step, program/partner, contact count, last updated. Use client_id when it's known from page context; otherwise use name.",
    input_schema: {
      type: "object",
      properties: {
        client_id: { type: "string", description: "The engagement's UUID, if known (e.g. from page context)." },
        name: { type: "string", description: "The engagement's name, if id is not known. Partial match is fine." },
      },
    },
  },
  {
    name: "list_applications",
    description: "List engagement applications (companies applying to become engagements), optionally filtered by status.",
    input_schema: {
      type: "object",
      properties: {
        status: { type: "string", enum: ["pending", "accepted", "rejected"], description: "Omit to get all statuses." },
      },
    },
  },
  {
    name: "list_team",
    description: "List EG team members, optionally filtered by role.",
    input_schema: {
      type: "object",
      properties: {
        role: {
          type: "string",
          enum: ["consultant", "team_lead", "super_admin"],
          description: "consultant=Specialist, super_admin=Admin. Omit to get everyone.",
        },
      },
    },
  },
  {
    name: "get_hours_and_payroll",
    description:
      "Get logged hours and estimated payroll for a given month (defaults to the current month if omitted), optionally filtered to one specialist by name.",
    input_schema: {
      type: "object",
      properties: {
        month: { type: "string", description: "Month in YYYY-MM format. Defaults to the current month if omitted." },
        specialist_name: { type: "string", description: "Filter to one specialist's hours by full or partial name." },
      },
    },
  },
  {
    name: "list_programs",
    description: "List Econ Dev partner programs and how many engagements are linked to each.",
    input_schema: { type: "object", properties: {} },
  },
];

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
    const userName = profile?.full_name || "there";
    const roleLabel = ROLE_LABELS[role] || role;

    const pageHelp =
      (pageKey && PAGE_HELP[pageKey]) ||
      "A page inside the EG Dashboard app, an internal tool EG Group uses to manage economic gardening engagements with client companies.";

    let contextNote = `You're answering a question from ${userName}, signed in as a ${roleLabel}. They are currently on: ${pageContext || pageKey || "an EG Dashboard page"}.\n\nAbout this page: ${pageHelp}`;
    if (clientId) contextNote += `\n\nThe engagement currently open on screen has id: ${clientId}. If the user refers to "this engagement" and you need detail beyond what's already implied, call get_engagement_detail with this client_id.`;

    const answer = isAdmin
      ? await answerAsAdmin(userClient, question, contextNote)
      : await answerAsNonAdmin(question, contextNote);

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

const STYLE_INSTRUCTIONS =
  "Keep answers short (2-6 sentences, or a short list if that's clearer), specific, and friendly. Plain text with occasional **bold** for key terms or numbers -- no headers.";

// ---------- Non-admin path: no tools, no data access, just app help ----------
async function answerAsNonAdmin(question: string, contextNote: string): Promise<string> {
  const system = `You are "Ask AI," a helpful assistant embedded in the EG Dashboard app, an internal tool EG Group's staff use to manage economic gardening engagements.

${contextNote}

${STYLE_INSTRUCTIONS}

This user is NOT an Admin, so you have not been given any live data access -- do not claim to know specific figures (hours, payroll, budgets, counts, other engagements' details, etc.). If they ask for something like that, tell them to check the relevant section on this page, or ask an Admin. Focus on explaining how to use the app, where to find things, and how to phrase useful questions.`;

  const res = await callClaude({ system, messages: [{ role: "user", content: question }] });
  return extractText(res);
}

// ---------- Admin path: tool-use loop against live Supabase data ----------
async function answerAsAdmin(userClient: SupabaseClient, question: string, contextNote: string): Promise<string> {
  const system = `You are "Ask AI," a helpful assistant embedded in the EG Dashboard app, an internal tool EG Group's staff use to manage economic gardening engagements.

${contextNote}

${STYLE_INSTRUCTIONS}

This user is an Admin, so you have tools available to query live EG Group data in Supabase -- use them whenever the question needs current figures, names, or status, regardless of what page they're currently on. Call as many tools, in as many rounds, as you need to fully answer. Only state facts that came back from a tool call; never invent names or numbers. If a tool returns no matching data, say so plainly.`;

  const messages: any[] = [{ role: "user", content: question }];

  for (let round = 0; round < MAX_TOOL_ROUNDS; round++) {
    const res = await callClaude({ system, messages, tools: ADMIN_TOOLS });

    if (res.stop_reason !== "tool_use") {
      return extractText(res);
    }

    messages.push({ role: "assistant", content: res.content });

    const toolResults = [];
    for (const block of res.content) {
      if (block.type !== "tool_use") continue;
      let result;
      try {
        result = await runAdminTool(userClient, block.name, block.input || {});
      } catch (err) {
        console.error(`Tool ${block.name} failed:`, err);
        result = { error: "That lookup failed. Try rephrasing or asking about something else." };
      }
      toolResults.push({ type: "tool_result", tool_use_id: block.id, content: JSON.stringify(result) });
    }
    messages.push({ role: "user", content: toolResults });
  }

  return "That question needed more lookups than I could complete in one go -- try breaking it into a couple of smaller questions.";
}

async function callClaude(opts: { system: string; messages: any[]; tools?: any[] }): Promise<any> {
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": ANTHROPIC_API_KEY!,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: CLAUDE_MODEL,
      max_tokens: 800,
      system: opts.system,
      messages: opts.messages,
      ...(opts.tools ? { tools: opts.tools } : {}),
    }),
  });
  if (!res.ok) {
    const errText = await res.text();
    console.error("Claude API error:", res.status, errText);
    throw new Error(`Claude API error ${res.status}`);
  }
  return res.json();
}

function extractText(claudeResponse: any): string {
  const textBlock = (claudeResponse?.content || []).find((b: any) => b.type === "text");
  return textBlock?.text || "Sorry, I couldn't come up with an answer to that.";
}

// ---------- Tool implementations ----------
// Every one of these runs on the forwarded-user-JWT client -- same RLS a
// logged-in Admin already has in the app itself. Column/table names here
// match what the front-end pages already query.
async function runAdminTool(userClient: SupabaseClient, name: string, input: Record<string, any>): Promise<unknown> {
  switch (name) {
    case "list_engagements": {
      let query = userClient
        .from("clients")
        .select("name, project_status, status, budget_hours_available, updated_at, econ_dev_companies(name)");
      if (input.project_status) query = query.eq("project_status", input.project_status);
      if (input.search) query = query.ilike("name", `%${input.search}%`);
      const { data, error } = await query.order("name").limit(50);
      if (error) return { error: error.message };
      return (data || []).map((c: any) => ({
        name: c.name,
        project_status: c.project_status,
        program: c.econ_dev_companies?.name || null,
        budget_hours_available: c.budget_hours_available,
        last_updated: c.updated_at?.slice(0, 10) || null,
      }));
    }

    case "get_engagement_detail": {
      let query = userClient
        .from("clients")
        .select("id, name, project_status, status, budget_hours_available, updated_at, top_business_issues, econ_dev_companies(name)");
      if (input.client_id) query = query.eq("id", input.client_id);
      else if (input.name) query = query.ilike("name", `%${input.name}%`);
      else return { error: "Provide client_id or name." };

      const { data: client, error } = await query.limit(1).maybeSingle();
      if (error) return { error: error.message };
      if (!client) return { error: "No matching engagement found." };

      const [{ data: assignments }, { data: nextSteps }, { data: contacts }] = await Promise.all([
        userClient.from("client_assignments").select("specialty_type, hours_allotted, is_team_lead, users(full_name)").eq("client_id", client.id),
        userClient.from("client_next_steps").select("description").eq("client_id", client.id).eq("completed", false).order("sort_order").limit(3),
        userClient.from("client_contacts").select("name, email").eq("client_id", client.id),
      ]);

      return {
        name: client.name,
        project_status: client.project_status,
        lifecycle_status: client.status,
        program: (client as any).econ_dev_companies?.name || null,
        budget_hours_available: client.budget_hours_available,
        hours_allotted_total: (assignments || []).reduce((s: number, a: any) => s + Number(a.hours_allotted || 0), 0),
        team: (assignments || []).map((a: any) => ({
          name: a.users?.full_name || null,
          specialty: a.specialty_type,
          hours_allotted: a.hours_allotted,
          is_team_lead: a.is_team_lead,
        })),
        open_next_steps: (nextSteps || []).map((n: any) => n.description),
        contacts_on_file: (contacts || []).length,
        last_updated: client.updated_at?.slice(0, 10) || null,
      };
    }

    case "list_applications": {
      let query = userClient.from("client_applications").select("company_name, status, submitted_at");
      if (input.status) query = query.eq("status", input.status);
      const { data, error } = await query.order("submitted_at", { ascending: false }).limit(50);
      if (error) return { error: error.message };
      return (data || []).map((a: any) => ({
        company_name: a.company_name,
        status: a.status,
        submitted_at: a.submitted_at?.slice(0, 10) || null,
      }));
    }

    case "list_team": {
      let query = userClient.from("users").select("full_name, role, email");
      if (input.role) query = query.eq("role", input.role);
      const { data, error } = await query.order("full_name").limit(100);
      if (error) return { error: error.message };
      return (data || []).map((u: any) => ({ name: u.full_name, role: ROLE_LABELS[u.role] || u.role, email: u.email }));
    }

    case "get_hours_and_payroll": {
      const now = new Date();
      let year = now.getFullYear();
      let month = now.getMonth(); // 0-indexed
      if (input.month && /^\d{4}-\d{2}$/.test(input.month)) {
        const [y, m] = input.month.split("-").map(Number);
        year = y;
        month = m - 1;
      }
      const monthStart = new Date(year, month, 1).toISOString().slice(0, 10);
      const monthEnd = new Date(year, month + 1, 1).toISOString().slice(0, 10);

      let specialistId: string | null = null;
      let specialistName: string | undefined = input.specialist_name;
      if (specialistName) {
        const { data: match } = await userClient
          .from("users")
          .select("id, full_name")
          .ilike("full_name", `%${specialistName}%`)
          .limit(1)
          .maybeSingle();
        if (match) {
          specialistId = (match as any).id;
          specialistName = (match as any).full_name;
        } else {
          return { error: `No specialist found matching "${input.specialist_name}".` };
        }
      }

      let query = userClient.from("time_entries").select("hours, entry_date, consultant_id").gte("entry_date", monthStart).lt("entry_date", monthEnd);
      if (specialistId) query = query.eq("consultant_id", specialistId);
      const { data: entries, error } = await query;
      if (error) return { error: error.message };

      const totalHours = (entries || []).reduce((s: number, e: any) => s + Number(e.hours || 0), 0);
      const { data: orgSettings } = await userClient.from("organization_settings").select("hourly_rate").limit(1).maybeSingle();
      const rate = (orgSettings as any)?.hourly_rate;

      return {
        month: `${year}-${String(month + 1).padStart(2, "0")}`,
        specialist: specialistName || "all specialists",
        total_hours: Number(totalHours.toFixed(2)),
        hourly_rate: rate ?? null,
        estimated_payroll: rate ? Number((totalHours * Number(rate)).toFixed(2)) : null,
      };
    }

    case "list_programs": {
      const [{ data: programs, error: pErr }, { data: clients, error: cErr }] = await Promise.all([
        userClient.from("econ_dev_companies").select("id, name, code"),
        userClient.from("clients").select("econ_dev_company_id"),
      ]);
      if (pErr) return { error: pErr.message };
      if (cErr) return { error: cErr.message };
      const counts: Record<string, number> = {};
      for (const c of clients || []) {
        const id = (c as any).econ_dev_company_id;
        if (id) counts[id] = (counts[id] || 0) + 1;
      }
      return (programs || []).map((p: any) => ({ name: p.name, code: p.code, engagement_count: counts[p.id] || 0 }));
    }

    default:
      return { error: `Unknown tool: ${name}` };
  }
}
