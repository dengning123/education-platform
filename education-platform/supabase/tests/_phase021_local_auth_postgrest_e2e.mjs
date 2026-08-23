import { createHmac, randomUUID } from "node:crypto";
import { spawnSync } from "node:child_process";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function fail(message) {
  throw new Error(message);
}

function command(bin, args, options = {}) {
  const result = spawnSync(bin, args, {
    encoding: "utf8",
    ...options,
  });
  if (result.status !== 0) {
    fail(`${bin} failed with status ${result.status ?? "unknown"}`);
  }
  return result.stdout;
}

function localUrl(value, label) {
  const url = new URL(value);
  if (url.hostname !== "127.0.0.1" && url.hostname !== "localhost") {
    fail(`${label} must target the disposable local Supabase stack`);
  }
  return url;
}

function readLocalStatus() {
  const supabaseBin = process.env.SUPABASE_BIN ?? "supabase";
  const output = command(supabaseBin, ["status", "--output", "json"]);
  const start = output.indexOf("{");
  if (start < 0) fail("Supabase status did not return JSON");
  return JSON.parse(output.slice(start));
}

function base64url(value) {
  return Buffer.from(value).toString("base64url");
}

function expiredJwt(secret, subject) {
  const header = base64url(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const payload = base64url(JSON.stringify({
    aud: "authenticated",
    exp: 1,
    iat: 1,
    role: "authenticated",
    sub: subject,
  }));
  const unsigned = `${header}.${payload}`;
  const signature = createHmac("sha256", secret)
    .update(unsigned)
    .digest("base64url");
  return `${unsigned}.${signature}`;
}

async function jsonRequest(url, init, expectedStatuses) {
  const response = await fetch(url, init);
  if (!expectedStatuses.includes(response.status)) {
    fail(`Unexpected local HTTP status ${response.status}`);
  }
  const text = await response.text();
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch {
    fail("Local endpoint returned malformed JSON");
  }
}

async function signUp(apiUrl, anonKey, label) {
  const password = `Phase021-${randomUUID()}-Aa1!`;
  const email = `phase021-${label}-${randomUUID()}@test.invalid`;
  const data = await jsonRequest(
    new URL("/auth/v1/signup", apiUrl),
    {
      method: "POST",
      headers: { apikey: anonKey, "content-type": "application/json" },
      body: JSON.stringify({ email, password }),
    },
    [200],
  );
  if (!data?.user?.id || !uuidPattern.test(data.user.id)) {
    fail("Local Auth did not issue a valid user subject");
  }
  if (!data.access_token) {
    fail("Local Auth signup did not issue a session token");
  }
  return { id: data.user.id, token: data.access_token };
}

function rpcHeaders(anonKey, token) {
  const headers = { apikey: anonKey, "content-type": "application/json" };
  if (token) headers.authorization = `Bearer ${token}`;
  return headers;
}

async function rpc(apiUrl, anonKey, token, functionName, body, statuses = [200]) {
  return jsonRequest(
    new URL(`/rest/v1/rpc/${functionName}`, apiUrl),
    {
      method: "POST",
      headers: rpcHeaders(anonKey, token),
      body: JSON.stringify(body),
    },
    statuses,
  );
}

function databaseCommand(sql, options = {}) {
  if (process.env.PSQL_BIN) {
    return command(
      process.env.PSQL_BIN,
      [databaseUrl, "-At", "-v", "ON_ERROR_STOP=1", "-c", sql],
      options,
    );
  }
  const dockerBin = process.env.DOCKER_BIN ?? "docker";
  const databaseContainer = process.env.PHASE021_DB_CONTAINER;
  if (!databaseContainer || !/^supabase_db_[A-Za-z0-9_.-]+$/.test(databaseContainer)) {
    fail("Set PSQL_BIN or the exact disposable PHASE021_DB_CONTAINER name");
  }
  return command(
    dockerBin,
    [
      "exec", databaseContainer, "psql", "-U", "postgres", "-d", "postgres",
      "-At", "-v", "ON_ERROR_STOP=1", "-c", sql,
    ],
    options,
  );
}

function assertSubjectBinding(authUserId) {
  const sql = `select count(*) from private.student_identities where auth_user_id = '${authUserId}'::uuid;`;
  const count = databaseCommand(sql).trim();
  if (count !== "1") fail("PostgREST request subject did not bind to the Auth-issued user");
}

function cleanup(authUserIds) {
  const validIds = authUserIds.filter((value) => uuidPattern.test(value));
  if (validIds.length === 0) return;
  const list = validIds.map((value) => `'${value}'::uuid`).join(",");
  const sql = `
    do $cleanup$
    declare v_student_id uuid;
    begin
      for v_student_id in
        select student_id from private.student_identities
        where auth_user_id in (${list})
      loop
        perform public.delete_student_data(
          v_student_id,
          'PHASE021_LOCAL_AUTH_POSTGREST_E2E_CLEANUP'
        );
      end loop;
      delete from auth.users where id in (${list});
    end
    $cleanup$;
  `;
  databaseCommand(sql, {
    stdio: "ignore",
  });
}

const status = readLocalStatus();
const apiUrl = localUrl(
  process.env.PHASE021_SUPABASE_URL ?? status.API_URL,
  "Supabase API URL",
);
const databaseUrl = localUrl(
  process.env.PHASE021_DATABASE_URL ?? status.DB_URL,
  "Supabase database URL",
).toString();
const anonKey = process.env.PHASE021_ANON_KEY ?? status.ANON_KEY;
const jwtSecret = process.env.PHASE021_JWT_SECRET ?? status.JWT_SECRET;

if (!anonKey || !jwtSecret) fail("Local Supabase status is missing required test credentials");

const authUserIds = [];
try {
  const owner = await signUp(apiUrl, anonKey, "owner");
  const other = await signUp(apiUrl, anonKey, "other");
  authUserIds.push(owner.id, other.id);

  await rpc(apiUrl, anonKey, owner.token, "bootstrap_profile_identity_v019", {});
  const ownerDraft = await rpc(
    apiUrl,
    anonKey,
    owner.token,
    "create_or_resume_profile_draft_v019",
    { p_operation_id: randomUUID() },
  );
  if (!uuidPattern.test(ownerDraft?.profileVersionId ?? "")) {
    fail("Owner Profile draft was not created through PostgREST");
  }
  assertSubjectBinding(owner.id);

  await rpc(apiUrl, anonKey, other.token, "bootstrap_profile_identity_v019", {});
  const otherDraft = await rpc(
    apiUrl,
    anonKey,
    other.token,
    "create_or_resume_profile_draft_v019",
    { p_operation_id: randomUUID() },
  );
  if (!uuidPattern.test(otherDraft?.profileVersionId ?? "")) {
    fail("Unrelated Profile draft was not created through PostgREST");
  }
  assertSubjectBinding(other.id);

  const unrelatedRead = await rpc(
    apiUrl,
    anonKey,
    other.token,
    "get_profile_document_v019",
    { p_profile_version_id: ownerDraft.profileVersionId },
    [500],
  );
  if (unrelatedRead?.code !== "P0002" || unrelatedRead?.message !== "PROFILE_NOT_FOUND") {
    fail("Unrelated Auth subject did not fail with the closed Profile not-found contract");
  }

  await rpc(apiUrl, anonKey, null, "bootstrap_profile_identity_v019", {}, [401, 403]);
  await rpc(
    apiUrl,
    anonKey,
    expiredJwt(jwtSecret, owner.id),
    "bootstrap_profile_identity_v019",
    {},
    [401],
  );
  await rpc(
    apiUrl,
    anonKey,
    "not-a-jwt",
    "bootstrap_profile_identity_v019",
    {},
    [401],
  );

  await rpc(
    apiUrl,
    anonKey,
    other.token,
    "bootstrap_profile_identity_v019",
    { p_auth_user_id: owner.id },
    [404],
  );

  console.log("Phase 021 real local Auth/PostgREST E2E: PASS");
} finally {
  cleanup(authUserIds);
}
