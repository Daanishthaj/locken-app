// Deletes the signed-in user's own Locken account.
//
// Security:
// - The gateway checks the request (verify_jwt = true), and the user is looked up on the server from the
//   token in the Authorization header. Nothing in the request body is trusted, so a caller can only ever
//   delete their own account. An API key alone (publishable or secret) is not a user and gets 401.
// - Accounts with an authenticator app must be at aal2 (the same rule the RLS policies enforce).
// - The admin key exists only in this function's environment and is never sent to the app. It's Supabase's
//   new secret key (SUPABASE_SECRET_KEYS, revocable on its own); the legacy service-role key is only a
//   fallback until legacy keys are turned off in the dashboard.
// - profiles and focus_sessions rows go with the user through ON DELETE CASCADE.
import { createClient } from "jsr:@supabase/supabase-js@2";

const json = (body: Record<string, unknown>, status: number) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

/** The project's default secret key, or the legacy service-role key while legacy keys are still enabled. */
function adminKey(): string | null {
  try {
    const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
    if (typeof keys.default === "string" && keys.default.length > 0) return keys.default;
  } catch {
    // Not set or not JSON: fall through to the legacy key.
  }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? null;
}

/** The `aal` claim of the user's JWT (already validated by getUser below). */
function assuranceLevel(jwt: string): string | null {
  try {
    const payload = jwt.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    return JSON.parse(atob(payload.padEnd(payload.length + ((4 - (payload.length % 4)) % 4), "="))).aal ?? null;
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const jwt = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!jwt || jwt.startsWith("sb_")) return json({ error: "Not signed in" }, 401);

  const key = adminKey();
  if (!key) {
    console.error("delete-account: no admin key configured");
    return json({ error: "Couldn't delete the account" }, 500);
  }
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Identity comes from the user's token only.
  const { data, error } = await admin.auth.getUser(jwt);
  const user = data?.user;
  if (error || !user) return json({ error: "Not signed in" }, 401);

  const hasVerifiedFactor = (user.factors ?? []).some((factor) => factor.status === "verified");
  if (hasVerifiedFactor && assuranceLevel(jwt) !== "aal2") {
    return json({ error: "Enter your authenticator code first" }, 403);
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) {
    console.error("delete-account failed", deleteError.message);
    return json({ error: "Couldn't delete the account" }, 500);
  }
  return json({ deleted: true }, 200);
});
