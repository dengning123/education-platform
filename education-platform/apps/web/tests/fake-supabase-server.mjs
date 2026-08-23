import { createServer } from "node:http";

const host = "127.0.0.1";
const port = 54321;
const publicKey = process.env.FAKE_SUPABASE_PUBLIC_KEY ?? "sb_publishable_phase4b1a_browser_test";
const allowedOrigin = process.env.FAKE_SUPABASE_ALLOWED_ORIGIN ?? "http://127.0.0.1:3100";
const now = "2026-08-23T00:00:00.000Z";

const users = new Map([
  ["alice@example.test", {
    id: "10000000-0000-4000-8000-000000000001",
    email: "alice@example.test",
    password: "alice-password-1A",
  }],
  ["bob@example.test", {
    id: "10000000-0000-4000-8000-000000000002",
    email: "bob@example.test",
    password: "bob-password-1A",
  }],
]);

const accessSessions = new Map();
const refreshSessions = new Map();
let sequence = 0;

function publicUser(user) {
  return {
    id: user.id,
    aud: "authenticated",
    role: "authenticated",
    email: user.email,
    email_confirmed_at: now,
    phone: "",
    app_metadata: { provider: "email", providers: ["email"] },
    user_metadata: {},
    identities: [],
    created_at: now,
    updated_at: now,
    is_anonymous: false,
  };
}

function jwt(user) {
  sequence += 1;
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const payload = {
    aud: "authenticated",
    exp: Math.floor(Date.now() / 1000) + 3600,
    iat: Math.floor(Date.now() / 1000),
    iss: `${allowedOrigin}/auth/v1`,
    role: "authenticated",
    sub: user.id,
    email: user.email,
    session_id: `phase4b1a-${sequence}`,
  };
  return `${encode({ alg: "HS256", typ: "JWT" })}.${encode(payload)}.test-signature-${sequence}`;
}

function issueSession(user) {
  const accessToken = jwt(user);
  const refreshToken = `phase4b1a-refresh-${sequence}`;
  accessSessions.set(accessToken, user);
  refreshSessions.set(refreshToken, user);
  return {
    access_token: accessToken,
    token_type: "bearer",
    expires_in: 3600,
    expires_at: Math.floor(Date.now() / 1000) + 3600,
    refresh_token: refreshToken,
    user: publicUser(user),
  };
}

function headers(extra = {}) {
  return {
    "access-control-allow-origin": allowedOrigin,
    "access-control-allow-headers": "authorization, apikey, content-type, x-client-info, x-supabase-api-version",
    "access-control-allow-methods": "GET, POST, OPTIONS",
    "content-type": "application/json",
    vary: "Origin",
    ...extra,
  };
}

function send(response, status, body = null, extraHeaders = {}) {
  response.writeHead(status, headers(extraHeaders));
  response.end(body === null ? "" : JSON.stringify(body));
}

async function jsonBody(request) {
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  if (chunks.length === 0) return {};
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    return {};
  }
}

function bearer(request) {
  const authorization = request.headers.authorization ?? "";
  return authorization.startsWith("Bearer ") ? authorization.slice(7) : null;
}

function revokeEmail(email) {
  for (const [token, user] of accessSessions) {
    if (user.email === email) accessSessions.delete(token);
  }
  for (const [token, user] of refreshSessions) {
    if (user.email === email) refreshSessions.delete(token);
  }
}

const server = createServer(async (request, response) => {
  const url = new URL(request.url ?? "/", `http://${host}:${port}`);

  if (request.method === "OPTIONS") {
    send(response, 204);
    return;
  }
  if (url.pathname === "/health") {
    send(response, 200, { ok: true });
    return;
  }
  if (url.pathname === "/__test__/reset" && request.method === "POST") {
    accessSessions.clear();
    refreshSessions.clear();
    send(response, 200, { ok: true });
    return;
  }
  if (url.pathname === "/__test__/revoke" && request.method === "POST") {
    const body = await jsonBody(request);
    revokeEmail(String(body.email ?? ""));
    send(response, 200, { ok: true });
    return;
  }

  if (request.headers.apikey !== publicKey) {
    send(response, 401, { message: "Public key required" });
    return;
  }

  if (url.pathname === "/auth/v1/token" && request.method === "POST") {
    const body = await jsonBody(request);
    const grantType = url.searchParams.get("grant_type");

    if (grantType === "password") {
      const user = users.get(String(body.email ?? "").toLowerCase());
      if (!user || user.password !== body.password) {
        send(response, 400, { error_code: "invalid_credentials", msg: "Internal fake dependency detail" });
        return;
      }
      send(response, 200, issueSession(user));
      return;
    }

    if (grantType === "refresh_token") {
      const user = refreshSessions.get(String(body.refresh_token ?? ""));
      if (!user) {
        send(response, 400, { error_code: "refresh_token_not_found", msg: "Expired test session" });
        return;
      }
      send(response, 200, issueSession(user));
      return;
    }
  }

  if (url.pathname === "/auth/v1/user" && request.method === "GET") {
    const user = accessSessions.get(bearer(request));
    if (!user) {
      send(response, 401, { message: "Invalid JWT" });
      return;
    }
    send(response, 200, publicUser(user));
    return;
  }

  if (url.pathname === "/auth/v1/logout" && request.method === "POST") {
    const token = bearer(request);
    const user = accessSessions.get(token);
    if (user) revokeEmail(user.email);
    send(response, 204);
    return;
  }

  send(response, 404, { message: "Not found" });
});

server.listen(port, host, () => {
  process.stdout.write(`fake-supabase-ready:${port}\n`);
});

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
