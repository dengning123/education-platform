import { randomUUID } from "node:crypto";
import { spawnSync } from "node:child_process";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function fail(message) {
  throw new Error(message);
}

function command(bin, args, options = {}) {
  const result = spawnSync(bin, args, { encoding: "utf8", ...options });
  if (result.status !== 0) fail(`${bin} failed with status ${result.status ?? "unknown"}`);
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
  const output = command(process.env.SUPABASE_BIN ?? "supabase", ["status", "--output", "json"]);
  const start = output.indexOf("{");
  if (start < 0) fail("Supabase status did not return JSON");
  return JSON.parse(output.slice(start));
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
  const data = await jsonRequest(
    new URL("/auth/v1/signup", apiUrl),
    {
      method: "POST",
      headers: { apikey: anonKey, "content-type": "application/json" },
      body: JSON.stringify({
        email: `phase024-${label}-${randomUUID()}@test.invalid`,
        password: `Phase024-${randomUUID()}-Aa1!`,
      }),
    },
    [200],
  );
  if (!data?.user?.id || !uuidPattern.test(data.user.id) || !data.access_token) {
    fail("Local Auth did not issue a valid subject and session");
  }
  return { id: data.user.id, token: data.access_token };
}

async function rpc(apiUrl, anonKey, token, name, body, statuses = [200]) {
  const headers = { apikey: anonKey, "content-type": "application/json" };
  if (token) headers.authorization = `Bearer ${token}`;
  return jsonRequest(
    new URL(`/rest/v1/rpc/${name}`, apiUrl),
    { method: "POST", headers, body: JSON.stringify(body) },
    statuses,
  );
}

function databaseCommand(sql, options = {}) {
  const container = process.env.PHASE024_DB_CONTAINER;
  if (!container || !/^supabase_db_[A-Za-z0-9_.-]+$/.test(container)) {
    fail("Set the exact disposable PHASE024_DB_CONTAINER name");
  }
  return command(
    process.env.DOCKER_BIN ?? "docker",
    ["exec", container, "psql", "-U", "postgres", "-d", "postgres", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql],
    options,
  );
}

function cleanup(authUserIds) {
  const ids = authUserIds.filter((value) => uuidPattern.test(value));
  if (ids.length === 0) return;
  const list = ids.map((value) => `'${value}'::uuid`).join(",");
  databaseCommand(`
    do $cleanup$
    declare v_student_id uuid;
    begin
      for v_student_id in
        select student_id from private.student_identities
        where auth_user_id in (${list})
      loop
        perform public.delete_student_data(
          v_student_id, 'PHASE024_LOCAL_AUTH_POSTGREST_E2E_CLEANUP'
        );
      end loop;
      delete from auth.users where id in (${list});
    end
    $cleanup$;
  `, { stdio: "ignore" });
}

const status = readLocalStatus();
const apiUrl = localUrl(process.env.PHASE024_SUPABASE_URL ?? status.API_URL, "Supabase API URL");
const anonKey = process.env.PHASE024_ANON_KEY ?? status.ANON_KEY;
if (!anonKey) fail("Local Supabase status is missing the anonymous credential");

const authUserIds = [];
try {
  const owner = await signUp(apiUrl, anonKey, "owner");
  const unrelated = await signUp(apiUrl, anonKey, "unrelated");
  authUserIds.push(owner.id, unrelated.id);

  await rpc(apiUrl, anonKey, owner.token, "bootstrap_profile_identity_v019", {});
  const draft = await rpc(
    apiUrl,
    anonKey,
    owner.token,
    "create_or_resume_profile_draft_v019",
    { p_operation_id: randomUUID() },
  );
  if (!uuidPattern.test(draft?.profileVersionId)) fail("Owner draft was not created");

  const definitions = await rpc(
    apiUrl,
    anonKey,
    owner.token,
    "get_profile_assessment_definitions_v024",
    {},
  );
  const definitionKeys = ["definitions", "releaseCode", "releaseOrdinal", "schemaVersion"];
  if (
    JSON.stringify(Object.keys(definitions).sort()) !== JSON.stringify(definitionKeys)
    || definitions.schemaVersion !== "PROFILE_ASSESSMENT_DEFINITIONS_V024"
    || definitions.releaseCode !== "v0.1"
    || definitions.releaseOrdinal !== 1
    || !Array.isArray(definitions.definitions)
    || definitions.definitions.length !== 0
  ) {
    fail("Production local stack did not keep real assessments unsupported");
  }

  const projection = await rpc(
    apiUrl,
    anonKey,
    owner.token,
    "get_profile_taxonomy_projection_v024",
    { p_profile_version_id: draft.profileVersionId },
  );
  if (
    projection.schemaVersion !== "PROFILE_TAXONOMY_PROJECTION_V024"
    || !Array.isArray(projection.concepts)
    || projection.concepts.length !== 0
  ) {
    fail("Empty owner Profile escaped the closed referenced-only projection");
  }

  await rpc(apiUrl, anonKey, unrelated.token, "bootstrap_profile_identity_v019", {});
  const unrelatedResult = await rpc(
    apiUrl,
    anonKey,
    unrelated.token,
    "get_profile_taxonomy_projection_v024",
    { p_profile_version_id: draft.profileVersionId },
    [404, 500],
  );
  if (unrelatedResult?.code !== "P0002" || unrelatedResult?.message !== "PROFILE_NOT_FOUND") {
    fail("Unrelated Auth subject enumerated the owner Profile");
  }

  await rpc(
    apiUrl,
    anonKey,
    null,
    "get_profile_assessment_definitions_v024",
    {},
    [401, 403],
  );
  await rpc(
    apiUrl,
    anonKey,
    "malformed.jwt.value",
    "get_profile_assessment_definitions_v024",
    {},
    [401, 403],
  );
  await rpc(
    apiUrl,
    anonKey,
    owner.token,
    "get_profile_assessment_definitions_v024",
    { p_student_id: owner.id },
    [400, 404],
  );

  const direct = await jsonRequest(
    new URL("/rest/v1/profile_assessment_definitions_v024?select=*", apiUrl),
    {
      method: "GET",
      headers: { apikey: anonKey, authorization: `Bearer ${owner.token}` },
    },
    [401, 403, 404],
  );
  if (Array.isArray(direct) && direct.length > 0) {
    fail("Authenticated browser read the assessment authority table directly");
  }

  console.log("Phase 024 real local Auth/PostgREST admissibility E2E: PASS");
} finally {
  cleanup(authUserIds);
}
