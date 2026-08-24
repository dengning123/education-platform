import { randomUUID } from "node:crypto";
import { spawnSync } from "node:child_process";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const postgresUuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const exactResponseKeys = ["conceptKind", "options", "releaseCode", "releaseOrdinal", "schemaVersion"];
const exactOptionKeys = ["canonicalKey", "conceptId", "displayName"];

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
        email: `phase023-${label}-${randomUUID()}@test.invalid`,
        password: `Phase023-${randomUUID()}-Aa1!`,
      }),
    },
    [200],
  );
  if (!data?.user?.id || !uuidPattern.test(data.user.id) || !data.access_token) {
    fail("Local Auth did not issue a valid subject and session");
  }
  return { id: data.user.id, token: data.access_token };
}

async function rpc(apiUrl, anonKey, token, functionName, body, statuses = [200]) {
  const headers = { apikey: anonKey, "content-type": "application/json" };
  if (token) headers.authorization = `Bearer ${token}`;
  return jsonRequest(
    new URL(`/rest/v1/rpc/${functionName}`, apiUrl),
    { method: "POST", headers, body: JSON.stringify(body) },
    statuses,
  );
}

function databaseCommand(sql, options = {}) {
  if (process.env.PSQL_BIN) {
    return command(process.env.PSQL_BIN, [databaseUrl, "-At", "-v", "ON_ERROR_STOP=1", "-c", sql], options);
  }
  const databaseContainer = process.env.PHASE023_DB_CONTAINER;
  if (!databaseContainer || !/^supabase_db_[A-Za-z0-9_.-]+$/.test(databaseContainer)) {
    fail("Set PSQL_BIN or the exact disposable PHASE023_DB_CONTAINER name");
  }
  return command(
    process.env.DOCKER_BIN ?? "docker",
    ["exec", databaseContainer, "psql", "-U", "postgres", "-d", "postgres", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql],
    options,
  );
}

function cleanup(authUserIds) {
  const validIds = authUserIds.filter((value) => uuidPattern.test(value));
  if (validIds.length === 0) return;
  const list = validIds.map((value) => `'${value}'::uuid`).join(",");
  databaseCommand(`
    do $cleanup$
    declare v_student_id uuid;
    begin
      for v_student_id in
        select student_id from private.student_identities
        where auth_user_id in (${list})
      loop
        perform public.delete_student_data(
          v_student_id,
          'PHASE023_LOCAL_AUTH_POSTGREST_E2E_CLEANUP'
        );
      end loop;
      delete from auth.users where id in (${list});
    end
    $cleanup$;
  `, { stdio: "ignore" });
}

function assertClosedOptions(result, conceptKind, expectedKeys) {
  if (JSON.stringify(Object.keys(result).sort()) !== JSON.stringify(exactResponseKeys)) {
    fail("Taxonomy options escaped its closed top-level DTO");
  }
  if (
    result.schemaVersion !== "PROFILE_TAXONOMY_OPTIONS_V023"
    || result.releaseCode !== "v0.1"
    || result.releaseOrdinal !== 1
    || result.conceptKind !== conceptKind
    || !Array.isArray(result.options)
    || result.options.length !== expectedKeys.length
  ) {
    fail("Taxonomy options did not use the verified bounded release contract");
  }
  const keys = result.options.map((option) => {
    if (JSON.stringify(Object.keys(option).sort()) !== JSON.stringify(exactOptionKeys)
      || !postgresUuidPattern.test(option.conceptId)
      || typeof option.displayName !== "string") {
      fail("Taxonomy option escaped its closed item DTO");
    }
    return option.canonicalKey;
  });
  if (JSON.stringify(keys) !== JSON.stringify(expectedKeys)) {
    fail("Taxonomy options inventory or deterministic order drifted");
  }
}

const status = readLocalStatus();
const apiUrl = localUrl(process.env.PHASE023_SUPABASE_URL ?? status.API_URL, "Supabase API URL");
const databaseUrl = localUrl(process.env.PHASE023_DATABASE_URL ?? status.DB_URL, "Supabase database URL").toString();
const anonKey = process.env.PHASE023_ANON_KEY ?? status.ANON_KEY;
if (!anonKey) fail("Local Supabase status is missing the anonymous credential");

const authUserIds = [];
try {
  const owner = await signUp(apiUrl, anonKey, "owner");
  const unbound = await signUp(apiUrl, anonKey, "unbound");
  authUserIds.push(owner.id, unbound.id);

  await rpc(apiUrl, anonKey, owner.token, "bootstrap_profile_identity_v019", {});
  const assessments = await rpc(
    apiUrl,
    anonKey,
    owner.token,
    "get_profile_taxonomy_options_v023",
    { p_concept_kind: "ASSESSMENT" },
  );
  assertClosedOptions(assessments, "ASSESSMENT", [
    "ASSESSMENT.GMAT",
    "ASSESSMENT.GRE",
    "ASSESSMENT.IELTS",
    "ASSESSMENT.TOEFL",
  ]);
  if (assessments.options.some((option) => option.canonicalKey === "ASSESSMENT.DUOLINGO")) {
    fail("Taxonomy options invented an unseeded Duolingo concept");
  }

  const skills = await rpc(
    apiUrl,
    anonKey,
    owner.token,
    "get_profile_taxonomy_options_v023",
    { p_concept_kind: "SKILL" },
  );
  assertClosedOptions(skills, "SKILL", ["SKILL.PYTHON", "SKILL.R", "SKILL.SQL"]);

  const unboundResult = await rpc(
    apiUrl,
    anonKey,
    unbound.token,
    "get_profile_taxonomy_options_v023",
    { p_concept_kind: "SKILL" },
    [500],
  );
  if (unboundResult?.code !== "P0002" || unboundResult?.message !== "PROFILE_NOT_FOUND") {
    fail("Unbound Auth subject escaped the trusted Profile subject requirement");
  }

  await rpc(
    apiUrl,
    anonKey,
    owner.token,
    "get_profile_taxonomy_options_v023",
    { p_concept_kind: "FIELD" },
    [400],
  );
  await rpc(
    apiUrl,
    anonKey,
    null,
    "get_profile_taxonomy_options_v023",
    { p_concept_kind: "ASSESSMENT" },
    [401, 403],
  );

  console.log("Phase 023 real local Auth/PostgREST taxonomy options E2E: PASS");
} finally {
  cleanup(authUserIds);
}
