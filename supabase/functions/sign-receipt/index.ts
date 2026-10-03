// =============================================================================
// Edge Function: sign-receipt
//
// Signs a receipt so it can't be faked. The signed text (the receipt's
// details) and the signature are saved on the receipt; the app prints them as
// a QR code, and anyone with the app can check the code with the PUBLIC key
// built into the app (lib/features/receipts/data/receipt_keys.dart), even
// offline. Changing a single character of a signed receipt breaks the check.
//
//   POST /functions/v1/sign-receipt
//   body: { "payment_id": "<uuid>" }
//   ->    { "payload": "{...}", "signature": "<base64url>", "key_id": "k1" }
//   Already signed? Returns the stored signature (signing never changes).
//
//   body: { "backfill": true }      (app admins only)
//   ->    { "signed": 12 }          signs up to 500 unsigned receipts
//
// Safety: the caller must be able to READ the payment (asked as the caller,
// so the database's own rules decide). The payload is built from the
// database, never from what the caller sends, so nobody can get their own
// text signed.
//
// Secrets (set once, never in the code or the repo):
//   RECEIPT_SIGNING_KEY     the Ed25519 private key, 32 bytes as base64url
//   RECEIPT_SIGNING_KEY_ID  its id, e.g. "k1" (printed in each receipt so a
//                           new key can be introduced later without breaking
//                           older receipts)
//   npx supabase secrets set RECEIPT_SIGNING_KEY=... RECEIPT_SIGNING_KEY_ID=k1 --project-ref ojhrcwvxauweepripcbi
//
// Deploy (from the rental_app folder):
//   npx supabase functions deploy sign-receipt --project-ref ojhrcwvxauweepripcbi --use-api
// =============================================================================

import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";
import { ed25519 } from "npm:@noble/curves@1.6.0/ed25519";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function fromBase64Url(text: string): Uint8Array {
  const base64 = text.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
}

function toBase64Url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

const receiptColumns =
  "payment_id, receipt_number, issued_at, signature, signed_payload, signing_key_id, " +
  "payment:payments(id, kind, amount, expected_amount, balance_after, months, " +
  "period_start, period_end, paid_on, reference_code, " +
  "property:properties(name, currency), " +
  "tenancy:tenancies(apartment:apartments(name), tenant:tenants(full_name)))";

// What gets signed. Short keys keep the QR code small. The keys are always
// in this order; the app checks the exact text, so the order doesn't matter
// for checking, only for reading.
// deno-lint-ignore no-explicit-any
function buildPayload(r: any, keyId: string): string {
  const p = r.payment;
  return JSON.stringify({
    v: 1,
    k: keyId,
    id: p.id,
    no: r.receipt_number,
    ref: p.reference_code,
    kind: p.kind,
    amt: p.amount,
    due: p.expected_amount,
    left: p.balance_after,
    cur: p.property.currency,
    paid: p.paid_on,
    from: p.period_start,
    to: p.period_end,
    mo: p.months,
    prop: p.property.name,
    unit: p.tenancy.apartment.name,
    ten: p.tenancy.tenant.full_name,
    iss: r.issued_at,
  });
}

// deno-lint-ignore no-explicit-any
async function sign(admin: SupabaseClient, r: any) {
  const keyId = Deno.env.get("RECEIPT_SIGNING_KEY_ID") ?? "k1";
  const privateKey = fromBase64Url(Deno.env.get("RECEIPT_SIGNING_KEY")!);
  const payload = buildPayload(r, keyId);
  const signature = toBase64Url(ed25519.sign(new TextEncoder().encode(payload), privateKey));

  // "signature is null": if two calls race, the first one's result stays
  // (Ed25519 gives the same signature for the same text anyway).
  const { error } = await admin.from("receipts")
    .update({
      signed_payload: payload,
      signature,
      signing_key_id: keyId,
      signed_at: new Date().toISOString(),
    })
    .eq("payment_id", r.payment_id)
    .is("signature", null);
  if (error) throw error;
  return { payload, signature, key_id: keyId };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Use POST" }, 405);
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Not logged in" }, 401);
  if (!Deno.env.get("RECEIPT_SIGNING_KEY")) {
    return json({ error: "Receipt signing isn't set up yet." }, 500);
  }

  // deno-lint-ignore no-explicit-any
  let body: any = {};
  try {
    body = await req.json();
  } catch {
    // handled below
  }

  const url = Deno.env.get("SUPABASE_URL")!;
  const asCaller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
  });
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  try {
    if (body.backfill === true) {
      const { data: isAdmin } = await asCaller.rpc("is_app_admin");
      if (isAdmin !== true) return json({ error: "Only the app admin can do this." }, 403);
      const { data: rows, error } = await admin.from("receipts")
        .select(receiptColumns).is("signature", null).limit(500);
      if (error) throw error;
      for (const r of rows ?? []) await sign(admin, r);
      return json({ signed: rows?.length ?? 0 });
    }

    const paymentId = body.payment_id;
    if (typeof paymentId !== "string") return json({ error: "payment_id is required" }, 400);

    // May the caller see this payment? (RLS decides: staff with money
    // permission, the tenant, or the app admin.)
    const { data: visible } = await asCaller.from("payments")
      .select("id").eq("id", paymentId).maybeSingle();
    if (!visible) return json({ error: "Payment not found" }, 404);

    const { data: r, error } = await admin.from("receipts")
      .select(receiptColumns).eq("payment_id", paymentId).single();
    if (error) throw error;
    if (r.signature) {
      return json({ payload: r.signed_payload, signature: r.signature, key_id: r.signing_key_id });
    }
    return json(await sign(admin, r));
  } catch (e) {
    return json({ error: (e as Error).message ?? String(e) }, 500);
  }
});
