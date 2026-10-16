// send-push: delivers a notification row to the user's Android devices through Firebase Cloud Messaging (HTTP v1).
// Called by the database trigger eedb_push_dispatch() (pg_net). Auth = shared secret kept in private.app_config
// (verify_jwt is OFF on purpose; the secret header is checked below).
// Required Edge Function secret:  FCM_SERVICE_ACCOUNT_JSON  (the whole Firebase service-account JSON).
import { createClient } from "npm:@supabase/supabase-js@2";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

let cached: { token: string; exp: number } | null = null;

function b64url(input: ArrayBuffer | string): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : new Uint8Array(input);
  let s = "";
  bytes.forEach((b) => (s += String.fromCharCode(b)));
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// deno-lint-ignore no-explicit-any
async function getAccessToken(sa: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.exp - 60 > now) return cached.token;
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const pem = String(sa.private_key).replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claim}`));
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${header}.${claim}.${b64url(sig)}`,
    }),
  });
  const json = await res.json();
  if (!res.ok) throw new Error("OAuth failed: " + JSON.stringify(json));
  cached = { token: json.access_token, exp: now + (json.expires_in ?? 3600) };
  return cached.token;
}

const json = (obj: unknown, status = 200) =>
  new Response(JSON.stringify(obj), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const { data: secret } = await admin.rpc("eedb_push_secret");
  if (!secret || req.headers.get("x-eedb-secret") !== secret) return json({ error: "unauthorized" }, 401);

  let body: { user_id?: string; title?: string; body?: string; link?: string; notification_id?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad json" }, 400);
  }
  if (!body.user_id || !body.title) return json({ error: "user_id and title required" }, 400);

  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON");
  if (!raw) return json({ skipped: "FCM_SERVICE_ACCOUNT_JSON secret is not set" });

  const { data: tokens } = await admin.from("device_tokens").select("token").eq("user_id", body.user_id);
  if (!tokens || tokens.length === 0) return json({ sent: 0 });

  try {
    const sa = JSON.parse(raw);
    const accessToken = await getAccessToken(sa);
    const url = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;
    let sent = 0;
    const dead: string[] = [];
    for (const t of tokens) {
      const res = await fetch(url, {
        method: "POST",
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            token: t.token,
            // data-only: the app builds the notification itself so it works in foreground and background
            data: {
              title: String(body.title).slice(0, 120),
              body: String(body.body ?? "").slice(0, 300),
              link: String(body.link ?? ""),
              notification_id: String(body.notification_id ?? ""),
            },
            android: { priority: "HIGH" },
          },
        }),
      });
      if (res.ok) sent++;
      else if (res.status === 404 || res.status === 400) dead.push(t.token); // unregistered / invalid token
    }
    if (dead.length) await admin.from("device_tokens").delete().in("token", dead);
    return json({ sent, removed: dead.length });
  } catch (e) {
    return json({ error: String((e as Error).message ?? e) }, 500);
  }
});
