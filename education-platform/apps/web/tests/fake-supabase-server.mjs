import { createServer } from "node:http";

const host = "127.0.0.1";
const port = Number(process.env.FAKE_SUPABASE_PORT ?? "55431");
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
const profilesByUser = new Map();
let sequence = 0;
let profileSequence = 100;

function nextId() {
  profileSequence += 1;
  return `00000000-0000-4000-8000-${String(profileSequence).padStart(12, "0")}`;
}

function profileState(user) {
  let state = profilesByUser.get(user.id);
  if (!state) {
    state = { draft: null, frozen: new Map(), operations: new Map() };
    profilesByUser.set(user.id, state);
  }
  return state;
}

function readiness() {
  return {
    schemaVersion: "PROFILE_READINESS_V019",
    freezeReady: false,
    requiredScopeCount: 8,
    declaredRequiredScopeCount: 0,
    missingDeclarations: [
      { educationContextId: null, domain: "EDUCATION_HISTORY" },
      { educationContextId: null, domain: "COURSE_HISTORY" },
      { educationContextId: null, domain: "COURSE_MAPPING" },
      { educationContextId: null, domain: "TEST_HISTORY" },
      { educationContextId: null, domain: "EXPERIENCE_HISTORY" },
      { educationContextId: null, domain: "SKILL_HISTORY" },
      { educationContextId: null, domain: "PREFERENCES" },
      { educationContextId: null, domain: "GOALS" },
    ],
    declarations: [],
    mappingReadiness: [],
  };
}

function profileDocument(profile) {
  return {
    schemaVersion: "PROFILE_DOCUMENT_V019",
    profileVersionId: profile.id,
    versionNumber: profile.versionNumber,
    status: profile.status,
    revision: profile.revision,
    snapshotHash: profile.status === "FROZEN" ? "a".repeat(64) : null,
    frozenAt: profile.status === "FROZEN" ? now : null,
    readiness: readiness(),
    evidenceItems: [],
    degrees: [],
    courses: [],
    testScores: [],
    experiences: [],
    skills: [],
    experienceSkills: [],
    goals: [],
    preferences: [],
    mappings: [],
  };
}

function rpcError(response, status, message, code = "P0001") {
  send(response, status, { code, details: "Internal fake PostgREST detail", hint: "Internal fake hint", message });
}

function replayOrConflict(state, operationId, fingerprint) {
  const stored = state.operations.get(operationId);
  if (!stored) return null;
  return stored.fingerprint === fingerprint ? stored.result : "CONFLICT";
}

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
    profilesByUser.clear();
    profileSequence = 100;
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

  if (url.pathname.startsWith("/rest/v1/rpc/") && request.method === "POST") {
    const user = accessSessions.get(bearer(request));
    if (!user) {
      rpcError(response, 401, "PROFILE_AUTH_REQUIRED", "42501");
      return;
    }
    const state = profileState(user);
    const body = await jsonBody(request);
    const rpc = url.pathname.slice("/rest/v1/rpc/".length);

    if (rpc === "bootstrap_profile_identity_v019") {
      send(response, 200, { schemaVersion: "PROFILE_ACCOUNT_V019", accountState: "ACTIVE", hasCurrentDraft: state.draft !== null });
      return;
    }

    if (rpc === "create_or_resume_profile_draft_v019") {
      const operationId = String(body.p_operation_id ?? "");
      const fingerprint = "CREATE_OR_RESUME";
      const replay = replayOrConflict(state, operationId, fingerprint);
      if (replay === "CONFLICT") return rpcError(response, 409, "PROFILE_OPERATION_CONFLICT", "23505");
      if (replay) return send(response, 200, replay);
      if (!state.draft) {
        state.draft = { id: nextId(), versionNumber: state.frozen.size + 1, status: "DRAFT", revision: 0 };
      }
      const result = { schemaVersion: "PROFILE_OPERATION_RESULT_V019", operation: "CREATE_OR_RESUME", profileVersionId: state.draft.id, versionNumber: state.draft.versionNumber, status: "DRAFT", revision: state.draft.revision };
      state.operations.set(operationId, { fingerprint, result });
      send(response, 200, result);
      return;
    }

    if (rpc === "get_profile_document_v019") {
      const requested = body.p_profile_version_id;
      const profile = requested === null || requested === undefined ? state.draft : state.draft?.id === requested ? state.draft : state.frozen.get(requested);
      if (!profile) return rpcError(response, 404, "PROFILE_NOT_FOUND", "P0002");
      send(response, 200, profileDocument(profile));
      return;
    }

    if (rpc === "get_profile_readiness_v019") {
      const requested = body.p_profile_version_id;
      const profile = state.draft?.id === requested ? state.draft : state.frozen.get(requested);
      if (!profile) return rpcError(response, 404, "PROFILE_NOT_FOUND", "P0002");
      send(response, 200, readiness());
      return;
    }

    if (rpc === "mutate_profile_draft_v019") {
      if (!state.draft || state.draft.id !== body.p_profile_version_id) return rpcError(response, 404, "PROFILE_NOT_FOUND", "P0002");
      const operationId = String(body.p_operation_id ?? "");
      const fingerprint = JSON.stringify(body);
      const replay = replayOrConflict(state, operationId, fingerprint);
      if (replay === "CONFLICT") return rpcError(response, 409, "PROFILE_OPERATION_CONFLICT", "23505");
      if (replay) return send(response, 200, replay);
      if (state.draft.revision !== body.p_expected_revision) return rpcError(response, 409, "PROFILE_REVISION_CONFLICT", "40001");
      state.draft.revision += 1;
      const result = { schemaVersion: "PROFILE_OPERATION_RESULT_V019", operation: "MUTATE", command: body.p_command, profileVersionId: state.draft.id, revision: state.draft.revision, resourceId: null, resourceKey: null };
      state.operations.set(operationId, { fingerprint, result });
      send(response, 200, result);
      return;
    }

    if (rpc === "freeze_profile_draft_v019") {
      if (!state.draft || state.draft.id !== body.p_profile_version_id) return rpcError(response, 404, "PROFILE_NOT_FOUND", "P0002");
      const operationId = String(body.p_operation_id ?? "");
      const fingerprint = JSON.stringify(body);
      const replay = replayOrConflict(state, operationId, fingerprint);
      if (replay === "CONFLICT") return rpcError(response, 409, "PROFILE_OPERATION_CONFLICT", "23505");
      if (replay) return send(response, 200, replay);
      if (state.draft.revision !== body.p_expected_revision) return rpcError(response, 409, "PROFILE_REVISION_CONFLICT", "40001");
      state.draft.revision += 1;
      state.draft.status = "FROZEN";
      const frozen = state.draft;
      state.frozen.set(frozen.id, frozen);
      state.draft = null;
      const result = { schemaVersion: "PROFILE_OPERATION_RESULT_V019", operation: "FREEZE", profileVersionId: frozen.id, status: "FROZEN", revision: frozen.revision, document: profileDocument(frozen) };
      state.operations.set(operationId, { fingerprint, result });
      send(response, 200, result);
      return;
    }

    if (rpc === "fork_frozen_profile_to_draft_v020") {
      const source = state.frozen.get(body.p_source_profile_version_id);
      if (!source) return rpcError(response, 404, "PROFILE_NOT_FOUND", "P0002");
      const operationId = String(body.p_operation_id ?? "");
      const fingerprint = JSON.stringify(body);
      const replay = replayOrConflict(state, operationId, fingerprint);
      if (replay === "CONFLICT") return rpcError(response, 409, "PROFILE_OPERATION_CONFLICT", "23505");
      if (replay) return send(response, 200, replay);
      if (state.draft) return rpcError(response, 409, "PROFILE_ACTIVE_DRAFT_EXISTS", "55000");
      state.draft = { id: nextId(), versionNumber: source.versionNumber + 1, status: "DRAFT", revision: 0 };
      const result = { schemaVersion: "PROFILE_OPERATION_RESULT_V020", operation: "FORK_FROZEN", sourceProfileVersionId: source.id, profileVersionId: state.draft.id, versionNumber: state.draft.versionNumber, status: "DRAFT", revision: 0 };
      state.operations.set(operationId, { fingerprint, result });
      send(response, 200, result);
      return;
    }

    rpcError(response, 404, "PROFILE_NOT_FOUND", "P0002");
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
