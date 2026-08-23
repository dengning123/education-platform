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

function newDraft(versionNumber) {
  return {
    id: nextId(),
    versionNumber,
    status: "DRAFT",
    revision: 0,
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
    completeness: new Map(),
  };
}

function completenessKey(educationContextId, domain) {
  return `${educationContextId ?? "GLOBAL"}:${domain}`;
}

function readiness(profile) {
  const required = [
    { educationContextId: null, domain: "EDUCATION_HISTORY" },
    { educationContextId: null, domain: "TEST_HISTORY" },
    { educationContextId: null, domain: "EXPERIENCE_HISTORY" },
    { educationContextId: null, domain: "SKILL_HISTORY" },
    { educationContextId: null, domain: "PREFERENCES" },
    { educationContextId: null, domain: "GOALS" },
  ];
  const courseContexts = profile.degrees.length === 0 ? [null] : profile.degrees.map((degree) => degree.degreeId);
  for (const educationContextId of courseContexts) {
    required.push({ educationContextId, domain: "COURSE_HISTORY" });
    required.push({ educationContextId, domain: "COURSE_MAPPING" });
  }
  const declarations = [];
  const missingDeclarations = [];
  for (const scope of required) {
    const declaration = profile.completeness.get(completenessKey(scope.educationContextId, scope.domain));
    if (declaration) declarations.push(declaration);
    else missingDeclarations.push(scope);
  }
  const mappingReadiness = [
    ...profile.degrees.map((degree) => ({ recordType: "DEGREE", recordId: degree.degreeId, verified: false, mappingStatuses: [] })),
    ...profile.courses.map((course) => ({ recordType: "COURSE", recordId: course.courseId, verified: false, mappingStatuses: [] })),
  ];
  return {
    schemaVersion: "PROFILE_READINESS_V019",
    freezeReady: missingDeclarations.length === 0,
    requiredScopeCount: required.length,
    declaredRequiredScopeCount: declarations.length,
    missingDeclarations,
    declarations,
    mappingReadiness,
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
    readiness: readiness(profile),
    evidenceItems: profile.evidenceItems,
    degrees: profile.degrees,
    courses: profile.courses,
    testScores: profile.testScores,
    experiences: profile.experiences,
    skills: profile.skills,
    experienceSkills: profile.experienceSkills,
    goals: profile.goals,
    preferences: profile.preferences,
    mappings: profile.mappings,
  };
}

function replaceById(records, idKey, id, replacement) {
  const index = records.findIndex((record) => record[idKey] === id);
  if (index < 0) return false;
  records[index] = replacement;
  return true;
}

function removeById(records, idKey, id) {
  const index = records.findIndex((record) => record[idKey] === id);
  if (index < 0) return false;
  records.splice(index, 1);
  return true;
}

function applyProfileMutation(profile, command, payload) {
  if (command === "EVIDENCE_CREATE") {
    const evidenceId = nextId();
    profile.evidenceItems.push({ evidenceId, evidenceType: payload.evidenceType, locator: payload.locator ?? null, contentHash: payload.contentHash ?? null, observedAt: payload.observedAt ?? now });
    return evidenceId;
  }
  if (command === "EVIDENCE_UPDATE") {
    const replacement = { evidenceId: payload.evidenceId, evidenceType: payload.evidenceType, locator: payload.locator ?? null, contentHash: payload.contentHash ?? null, observedAt: payload.observedAt ?? now };
    return replaceById(profile.evidenceItems, "evidenceId", payload.evidenceId, replacement) ? payload.evidenceId : null;
  }
  if (command === "EVIDENCE_DELETE") {
    const inUse = [...profile.degrees, ...profile.courses, ...profile.testScores, ...profile.experiences, ...profile.skills, ...profile.mappings].some((record) => record.evidenceId === payload.evidenceId);
    if (inUse) return "PROFILE_EVIDENCE_IN_USE";
    return removeById(profile.evidenceItems, "evidenceId", payload.evidenceId) ? payload.evidenceId : null;
  }
  if (command === "DEGREE_CREATE") {
    const degreeId = nextId();
    profile.degrees.push({ degreeId, ...payload });
    return degreeId;
  }
  if (command === "DEGREE_UPDATE") {
    const replacement = { ...payload };
    return replaceById(profile.degrees, "degreeId", payload.degreeId, replacement) ? payload.degreeId : null;
  }
  if (command === "DEGREE_DELETE") {
    profile.courses = profile.courses.filter((course) => course.degreeId !== payload.degreeId);
    for (const key of [...profile.completeness.keys()]) {
      if (key.startsWith(`${payload.degreeId}:`)) profile.completeness.delete(key);
    }
    return removeById(profile.degrees, "degreeId", payload.degreeId) ? payload.degreeId : null;
  }
  if (command === "COURSE_CREATE") {
    const courseId = nextId();
    profile.courses.push({ courseId, ...payload });
    return courseId;
  }
  if (command === "COURSE_UPDATE") {
    const replacement = { ...payload };
    return replaceById(profile.courses, "courseId", payload.courseId, replacement) ? payload.courseId : null;
  }
  if (command === "COURSE_DELETE") {
    return removeById(profile.courses, "courseId", payload.courseId) ? payload.courseId : null;
  }
  if (command === "COMPLETENESS_UPSERT") {
    const key = completenessKey(payload.educationContextId ?? null, payload.domain);
    const current = profile.completeness.get(key);
    const completenessId = current?.completenessId ?? nextId();
    profile.completeness.set(key, { completenessId, educationContextId: payload.educationContextId ?? null, domain: payload.domain, completeness: payload.completeness, explanation: payload.completeness === "COMPLETE" ? null : payload.explanation });
    return completenessId;
  }
  if (command === "COMPLETENESS_DELETE") {
    const key = completenessKey(payload.educationContextId ?? null, payload.domain);
    const current = profile.completeness.get(key);
    profile.completeness.delete(key);
    return current?.completenessId ?? null;
  }
  return null;
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
  if (url.pathname === "/__test__/bump-profile-revision" && request.method === "POST") {
    const body = await jsonBody(request);
    const user = users.get(String(body.email ?? "").toLowerCase());
    const state = user ? profileState(user) : null;
    if (!state?.draft) return send(response, 404, { ok: false });
    state.draft.revision += 1;
    send(response, 200, { ok: true, revision: state.draft.revision });
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
        state.draft = newDraft(state.frozen.size + 1);
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
      send(response, 200, readiness(profile));
      return;
    }

    if (rpc === "get_profile_taxonomy_projection_v022") {
      const requested = body.p_profile_version_id;
      const profile = requested === null || requested === undefined ? state.draft : state.draft?.id === requested ? state.draft : state.frozen.get(requested);
      if (!profile) return rpcError(response, 404, "PROFILE_NOT_FOUND", "P0002");
      send(response, 200, {
        schemaVersion: "PROFILE_TAXONOMY_PROJECTION_V022",
        releaseCode: "v0.1",
        releaseOrdinal: 1,
        concepts: [],
      });
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
      const resourceId = applyProfileMutation(state.draft, body.p_command, body.p_payload ?? {});
      if (resourceId === "PROFILE_EVIDENCE_IN_USE") return rpcError(response, 409, resourceId, "55000");
      if (resourceId === null && !["EXPERIENCE_SKILL_LINK", "EXPERIENCE_SKILL_UNLINK"].includes(body.p_command)) return rpcError(response, 404, "PROFILE_CHILD_NOT_FOUND", "P0002");
      state.draft.revision += 1;
      const result = { schemaVersion: "PROFILE_OPERATION_RESULT_V019", operation: "MUTATE", command: body.p_command, profileVersionId: state.draft.id, revision: state.draft.revision, resourceId, resourceKey: null };
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
      state.draft = newDraft(source.versionNumber + 1);
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
