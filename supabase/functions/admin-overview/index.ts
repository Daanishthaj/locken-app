// The owner's private overview of Locken: accounts, feedback, usage, events, security checks, and the health of
// the database and update server. Also bans and unbans accounts.
//
// Security:
// - verify_jwt = true at the gateway, and the caller is looked up on the server from their token; nothing in the
//   request is trusted. Only accounts listed in public.admins (readable by the server alone) get data; everyone
//   else gets 403, so finding the endpoint or the button gives nobody anything.
// - Accounts with an authenticator app must be at aal2.
// - The admin key lives only in this function's environment (Supabase secret key, legacy key as fallback).
// - A ban can't target the caller or another admin; it also ends every session of the banned account.
import { createClient } from "jsr:@supabase/supabase-js@2";

const json = (body: Record<string, unknown>, status: number) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });

function adminKey(): string | null {
  try {
    const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
    if (typeof keys.default === "string" && keys.default.length > 0) return keys.default;
  } catch {
    // Not set or not JSON: fall through to the legacy key.
  }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? null;
}

function assuranceLevel(jwt: string): string | null {
  try {
    const payload = jwt.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    return JSON.parse(atob(payload.padEnd(payload.length + ((4 - (payload.length % 4)) % 4), "="))).aal ?? null;
  } catch {
    return null;
  }
}

const DAY = 24 * 60 * 60 * 1000;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const jwt = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!jwt || jwt.startsWith("sb_")) return json({ error: "Not signed in" }, 401);

  const key = adminKey();
  if (!key) return json({ error: "Not available" }, 500);
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: who, error: whoError } = await admin.auth.getUser(jwt);
  const user = who?.user;
  if (whoError || !user) return json({ error: "Not signed in" }, 401);
  if ((user.factors ?? []).some((f) => f.status === "verified") && assuranceLevel(jwt) !== "aal2") {
    return json({ error: "Enter your authenticator code first" }, 403);
  }

  const { data: adminRow } = await admin.from("admins").select("user_id").eq("user_id", user.id).maybeSingle();
  if (!adminRow) return json({ error: "Not allowed" }, 403);

  // A quiet check from the app just asks whether to show the Admin tab.
  const body = await req.json().catch(() => ({}));
  if (body?.check === true) return json({ admin: true }, 200);

  // Ban (sign-in refused, every session ended) or unban one account.
  if (body?.action === "ban" || body?.action === "unban") {
    const target = typeof body.userId === "string" ? body.userId : "";
    if (!UUID.test(target)) return json({ error: "Unknown account" }, 400);
    if (target === user.id) return json({ error: "You can't ban your own account" }, 400);
    const { data: targetAdmin } = await admin.from("admins").select("user_id").eq("user_id", target).maybeSingle();
    if (targetAdmin) return json({ error: "Admin accounts can't be banned" }, 400);
    const { error: banError } = await admin.auth.admin.updateUserById(target, {
      ban_duration: body.action === "ban" ? "876000h" : "none",
    });
    if (banError) return json({ error: "Couldn't change that account. Try again." }, banError.status === 404 ? 404 : 500);
    if (body.action === "ban") {
      const { error: endError } = await admin.rpc("admin_end_sessions", { target });
      if (endError) return json({ error: "Banned, but couldn't sign them out everywhere. Try again." }, 500);
    }
    return json({ ok: true }, 200);
  }

  const { data: list } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
  const now = Date.now();
  const users = (list?.users ?? []).map((u) => ({
    id: u.id,
    email: u.email ?? "",
    provider: (u.app_metadata?.provider as string) ?? "email",
    createdAt: u.created_at,
    lastSignInAt: u.last_sign_in_at ?? null,
    confirmed: Boolean(u.email_confirmed_at),
    banned: Boolean(u.banned_until && new Date(u.banned_until).getTime() > now),
  }));
  const emailFor = new Map(users.map((u) => [u.id, u.email]));
  const since = (iso: string | null, days: number) => iso !== null && now - new Date(iso).getTime() <= days * DAY;

  const { data: feedbackRows } = await admin
    .from("feedback")
    .select("id, user_id, rating, message, app_version, created_at")
    .order("created_at", { ascending: false })
    .limit(200);
  const feedback = (feedbackRows ?? []).map((f) => ({
    id: f.id,
    email: emailFor.get(f.user_id) ?? "deleted account",
    rating: f.rating,
    message: f.message,
    appVersion: f.app_version,
    createdAt: f.created_at,
  }));
  const ratings = feedback.map((f) => f.rating).filter((r): r is number => typeof r === "number");

  const { data: auditRows } = await admin.rpc("admin_recent_audit", { max_rows: 40 });
  const audit = (auditRows ?? []).map((a: Record<string, unknown>) => ({
    occurredAt: a.occurred_at,
    table: a.table_name,
    action: a.action,
    account: emailFor.get(String(a.row_id)) ?? emailFor.get(String(a.actor)) ?? null,
    changed: a.changed_columns,
  }));

  // Usage from data Supabase Auth already keeps (daily activity, app builds, sessions); see admin_analytics().
  const queryStarted = Date.now();
  const { data: analytics, error: analyticsError } = await admin.rpc("admin_analytics");
  const database = { ms: Date.now() - queryStarted, ok: !analyticsError };

  // The update server: what's live, and whether it answered and how fast (System Health).
  let liveVersion: Record<string, unknown> | null = null;
  const started = Date.now();
  let updateServer: Record<string, unknown> = { reachable: false, ms: null, status: null };
  try {
    const res = await fetch("https://locken-app.vercel.app/version.json", { cache: "no-store" });
    updateServer = { reachable: res.ok, ms: Date.now() - started, status: res.status };
    if (res.ok) {
      const v = await res.json();
      liveVersion = { version: v.version, build: v.build, notes: v.notes, maintenanceMode: v.maintenanceMode ?? false };
    }
  } catch {
    // The site being down doesn't stop the overview.
    updateServer = { reachable: false, ms: Date.now() - started, status: null };
  }

  return json({
    generatedAt: new Date().toISOString(),
    totals: {
      accounts: users.length,
      newLast7Days: users.filter((u) => since(u.createdAt, 7)).length,
      activeLast7Days: users.filter((u) => since(u.lastSignInAt, 7)).length,
      activeLast30Days: users.filter((u) => since(u.lastSignInAt, 30)).length,
      neverSignedIn: users.filter((u) => u.lastSignInAt === null).length,
      google: users.filter((u) => u.provider === "google").length,
      banned: users.filter((u) => u.banned).length,
      feedback: feedback.length,
      averageRating: ratings.length ? Math.round((ratings.reduce((a, b) => a + b, 0) / ratings.length) * 10) / 10 : null,
    },
    users: users.sort((a, b) => (b.lastSignInAt ?? "").localeCompare(a.lastSignInAt ?? "")),
    feedback,
    audit,
    analytics: analytics ?? null,
    liveVersion,
    updateServer,
    database,
  }, 200);
});
