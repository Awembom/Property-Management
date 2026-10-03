// =============================================================================
// Edge Function: reset-password
//
// Gives someone a temporary password, because without email nobody can reset
// their own. Called by the app as an owner or manager:
//
//   POST /functions/v1/reset-password
//   body: { "property_id": "<uuid>", "user_id": "<uuid>" }
//   (the app admin may leave property_id out)
//   ->    { "temporary_password": "K7Q-M4XP-2RTA" }
//
// Why a server function: changing another user's password needs the
// service-role (admin) key, which must NEVER be inside the app.
//
// Safety: before using admin rights, it asks the database
// (password_reset_target, run AS THE CALLER) whether the caller may reset
// this person. That function holds all the rules (role, same property only,
// no access to other properties). Nothing happens unless it says yes.
//
// The user must choose a new password at their next login: we set
// app_metadata.must_change_password, which users can't change themselves.
//
// Deploy (from the rental_app folder, after any change to this file):
//   npx supabase functions deploy reset-password --project-ref ojhrcwvxauweepripcbi --use-api
// (--use-api bundles on Supabase's side, so Docker isn't needed.)
// "Verify JWT" stays ON (the default): only logged-in users may call it.
// SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are provided
// automatically by Supabase; you don't set them.
// =============================================================================

import { createClient } from "npm:@supabase/supabase-js@2";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// 12 characters from a set that's easy to read out loud (no 0/O, 1/I/L),
// shown as XXXX-XXXX-XXXX. crypto.getRandomValues is a secure random source.
function temporaryPassword(): string {
  const chars = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
  const bytes = crypto.getRandomValues(new Uint8Array(12));
  const letters = Array.from(bytes, (b) => chars[b % chars.length]).join("");
  return `${letters.slice(0, 4)}-${letters.slice(4, 8)}-${letters.slice(8)}`;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Use POST" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Not logged in" }, 401);

  let propertyId: string | undefined;
  let userId: string | undefined;
  try {
    const body = await req.json();
    propertyId = body.property_id;
    userId = body.user_id;
  } catch {
    // handled below
  }
  if (!userId) {
    return json({ error: "user_id is required" }, 400);
  }

  const url = Deno.env.get("SUPABASE_URL")!;

  // 1. Ask the database, as the caller, whether this reset is allowed.
  const asCaller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: targetId, error: checkError } = await asCaller.rpc(
    "password_reset_target",
    { p_property_id: propertyId ?? null, p_user_id: userId },
  );
  if (checkError || !targetId) {
    // The database's message is written for people, e.g.
    // "You can only reset passwords for people below your role."
    return json({ error: checkError?.message ?? "Not allowed" }, 403);
  }

  // 2. Allowed: set the temporary password with admin rights.
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const password = temporaryPassword();
  const { error: updateError } = await admin.auth.admin.updateUserById(targetId, {
    password,
    app_metadata: { must_change_password: true },
  });
  if (updateError) return json({ error: updateError.message }, 500);

  // 3. Write it in the activity log (the app can't write there itself).
  const { data: caller } = await asCaller.auth.getUser();
  await admin.from("activity_log").insert({
    actor_id: caller.user?.id ?? null,
    property_id: propertyId ?? null,
    table_name: "auth",
    action: "password_reset",
    row_id: targetId,
  });

  return json({ temporary_password: password });
});
