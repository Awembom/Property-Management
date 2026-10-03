// =============================================================================
// Edge Function: send-push
//
// Sends waiting notifications (table `notifications`) to people's phones
// with Firebase Cloud Messaging (FCM HTTP v1). Called every minute by the
// database (dispatch_push(), pg_cron) with a shared secret; nobody else can
// call it.
//
// Too many at once: if someone has more than 2 waiting, or already got 4
// pushes in the last hour, they get ONE push instead: "You have N new
// notifications. Open Homedly to see them." (at most every 30 minutes).
// Everything stays in their in-app list either way.
//
// Secrets (set once, never in the code):
//   FCM_SERVICE_ACCOUNT    the Firebase service account JSON (project homedly-4a906)
//   PUSH_DISPATCH_SECRET   shared with the database (Vault: homedly_dispatch_secret)
//
// Deploy (from the rental_app folder):
//   npx supabase functions deploy send-push --project-ref ojhrcwvxauweepripcbi --use-api --no-verify-jwt
// (--no-verify-jwt: the database calls it with the shared secret, not a login.)
// =============================================================================

import { createClient } from "npm:@supabase/supabase-js@2";

type Notification = {
  id: string;
  user_id: string;
  title: string;
  body: string;
  route: string | null;
};

const encoder = new TextEncoder();

function base64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? encoder.encode(data) : data;
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// --- Google sign-in with the service account (OAuth 2, signed JWT) ---------

let cachedToken: { value: string; expires: number } | null = null;

async function accessToken(account: { client_email: string; private_key: string }): Promise<string> {
  if (cachedToken && cachedToken.expires > Date.now() + 60_000) return cachedToken.value;
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64url(JSON.stringify({
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const pem = account.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, encoder.encode(`${header}.${claims}`)),
  );
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${header}.${claims}.${base64url(signature)}`,
    }),
  });
  const json = await response.json();
  if (!response.ok) throw new Error(`Google sign-in failed: ${json.error ?? response.status}`);
  cachedToken = { value: json.access_token, expires: Date.now() + json.expires_in * 1000 };
  return cachedToken.value;
}

// --- Sending ------------------------------------------------------------------

Deno.serve(async (req) => {
  if (req.headers.get("x-dispatch-secret") !== Deno.env.get("PUSH_DISPATCH_SECRET")) {
    return new Response("Not allowed", { status: 401 });
  }
  const account = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT")!);
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  // Take what's waiting (marked handled at once, so it's never sent twice).
  const { data: claimed, error } = await admin.rpc("claim_pending_notifications", { p_limit: 300 });
  if (error) return Response.json({ error: error.message }, { status: 500 });
  const pending = (claimed ?? []) as Notification[];

  const byUser = new Map<string, Notification[]>();
  for (const n of pending) byUser.set(n.user_id, [...(byUser.get(n.user_id) ?? []), n]);

  let sent = 0, summaries = 0, removedTokens = 0;
  const token = pending.length ? await accessToken(account) : "";
  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`;

  // One push to every phone of a user. Phones that no longer exist are forgotten.
  async function push(tokens: string[], title: string, body: string, route: string | null) {
    for (const deviceToken of tokens) {
      const response = await fetch(fcmUrl, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            token: deviceToken,
            notification: { title, body },
            data: { route: route ?? "/home/notifications" },
            android: { priority: "HIGH", notification: { channel_id: "homedly" } },
          },
        }),
      });
      if (!response.ok) {
        const text = await response.text();
        if (response.status === 404 || text.includes("UNREGISTERED") || text.includes("INVALID_ARGUMENT")) {
          await admin.from("device_tokens").delete().eq("token", deviceToken);
          removedTokens++;
        } else {
          console.error("FCM error", response.status, text.slice(0, 200));
        }
      }
    }
  }

  for (const [userId, items] of byUser) {
    const { data: devices } = await admin.from("device_tokens").select("token").eq("user_id", userId);
    const tokens = (devices ?? []).map((d) => d.token as string);
    if (tokens.length === 0) continue; // no phone: it stays in their in-app list

    const hourAgo = new Date(Date.now() - 3600_000).toISOString();
    const { count: recent } = await admin.from("notifications")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId).eq("pushed", true).gte("sent_at", hourAgo);

    if (items.length <= 2 && (recent ?? 0) + items.length <= 4) {
      for (const n of items) {
        await push(tokens, n.title, n.body, n.route);
        sent++;
      }
      await admin.from("notifications").update({ pushed: true }).in("id", items.map((n) => n.id));
      continue;
    }

    // Too many: one summary, at most every 30 minutes.
    const { data: state } = await admin.from("push_state").select("last_summary_at").eq("user_id", userId)
      .maybeSingle();
    const last = state?.last_summary_at ? new Date(state.last_summary_at).getTime() : 0;
    if (Date.now() - last < 30 * 60_000) continue;
    const { count: unread } = await admin.from("notifications")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId).is("read_at", null);
    const n = unread ?? items.length;
    await push(tokens, `You have ${n} new notification${n === 1 ? "" : "s"}`,
               "Open Homedly to see them.", "/home/notifications");
    await admin.from("push_state").upsert({ user_id: userId, last_summary_at: new Date().toISOString() });
    summaries++;
  }

  return Response.json({ handled: pending.length, sent, summaries, removedTokens });
});
