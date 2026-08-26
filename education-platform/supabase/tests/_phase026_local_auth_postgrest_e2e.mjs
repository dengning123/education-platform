import { createHmac, randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
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

function localUrl(value) {
  const url = new URL(value);
  if (!["127.0.0.1", "localhost"].includes(url.hostname)) fail("M026 E2E must target disposable local Supabase");
  return url;
}

function readLocalStatus() {
  const output = command(process.env.SUPABASE_BIN ?? "supabase", ["status", "--output", "json"]);
  const start = output.indexOf("{");
  if (start < 0) fail("Supabase status did not return JSON");
  return JSON.parse(output.slice(start));
}

function expiredJwt(secret, subject) {
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const unsigned = `${encode({ alg: "HS256", typ: "JWT" })}.${encode({ aud: "authenticated", exp: 1, iat: 1, role: "authenticated", sub: subject })}`;
  return `${unsigned}.${createHmac("sha256", secret).update(unsigned).digest("base64url")}`;
}

async function jsonRequest(url, init, statuses) {
  const response = await fetch(url, init);
  if (!statuses.includes(response.status)) fail(`Unexpected local HTTP status ${response.status}`);
  const text = await response.text();
  if (!text) return null;
  try { return JSON.parse(text); } catch { fail("Local endpoint returned malformed JSON"); }
}

async function signUp(apiUrl, anonKey, label) {
  const data = await jsonRequest(new URL("/auth/v1/signup", apiUrl), {
    method: "POST",
    headers: { apikey: anonKey, "content-type": "application/json" },
    body: JSON.stringify({
      email: `phase026-${label}-${randomUUID()}@test.invalid`,
      password: `Phase026-${randomUUID()}-Aa1!`,
    }),
  }, [200]);
  if (!uuidPattern.test(data?.user?.id ?? "") || !data?.access_token) fail("Local Auth did not issue a valid session");
  return { id: data.user.id, token: data.access_token };
}

async function rpc(apiUrl, anonKey, token, name, body, statuses = [200]) {
  const headers = { apikey: anonKey, "content-type": "application/json" };
  if (token) headers.authorization = `Bearer ${token}`;
  return jsonRequest(new URL(`/rest/v1/rpc/${name}`, apiUrl), {
    method: "POST", headers, body: JSON.stringify(body),
  }, statuses);
}

function database(sql, options = {}) {
  const container = process.env.PHASE026_DB_CONTAINER;
  if (!container || !/^supabase_db_[A-Za-z0-9_.-]+$/.test(container)) fail("Exact disposable PHASE026_DB_CONTAINER is required");
  return command(process.env.DOCKER_BIN ?? "docker", [
    "exec", container, "psql", "-U", "postgres", "-d", "postgres",
    "-At", "-v", "ON_ERROR_STOP=1", "-c", sql,
  ], options).trim();
}

function installFixture(profileVersionId) {
  const container = process.env.PHASE026_DB_CONTAINER;
  if (!container || !uuidPattern.test(profileVersionId)) fail("Fixture identity is invalid");
  const sql = readFileSync(new URL("../../apps/web/tests/real-local/profile-eligibility-fit.fixture.sql", import.meta.url), "utf8");
  const result = spawnSync(process.env.DOCKER_BIN ?? "docker", [
    "exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres", "-At",
    "-v", "ON_ERROR_STOP=1", "-v", `profile_version_id=${profileVersionId}`, "-f", "-",
  ], { encoding: "utf8", input: sql, maxBuffer: 4 * 1024 * 1024 });
  if (result.status !== 0) fail("M026 local catalog fixture failed");
  const line = result.stdout.split("\n").map((value) => value.trim()).reverse().find((value) => value.startsWith("{"));
  if (!line) fail("Fixture did not return a closed identity");
  const fixture = JSON.parse(line);
  if (fixture.classification !== "GOLDEN PROGRAM RECORD + SYNTHETIC ELIGIBILITY RULES") fail("Fixture classification is not explicit");
  return fixture;
}

async function frozenProfile(apiUrl, anonKey, user) {
  await rpc(apiUrl, anonKey, user.token, "bootstrap_profile_identity_v019", {});
  const draft = await rpc(apiUrl, anonKey, user.token, "create_or_resume_profile_draft_v019", { p_operation_id: randomUUID() });
  let revision = draft.revision;
  await rpc(apiUrl, anonKey, user.token, "mutate_profile_draft_v019", {
    p_profile_version_id: draft.profileVersionId,
    p_operation_id: randomUUID(),
    p_expected_revision: revision,
    p_command: "EVIDENCE_CREATE",
    p_payload: { evidenceType: "SELF_REPORT" },
  });
  revision += 1;
  for (const domain of [
    "EDUCATION_HISTORY", "COURSE_HISTORY", "COURSE_MAPPING", "TEST_HISTORY",
    "EXPERIENCE_HISTORY", "SKILL_HISTORY", "PREFERENCES", "GOALS",
  ]) {
    await rpc(apiUrl, anonKey, user.token, "mutate_profile_draft_v019", {
      p_profile_version_id: draft.profileVersionId,
      p_operation_id: randomUUID(),
      p_expected_revision: revision,
      p_command: "COMPLETENESS_UPSERT",
      p_payload: { educationContextId: null, domain, completeness: "COMPLETE", explanation: null },
    });
    revision += 1;
  }
  const frozen = await rpc(apiUrl, anonKey, user.token, "freeze_profile_draft_v019", {
    p_profile_version_id: draft.profileVersionId,
    p_operation_id: randomUUID(),
    p_expected_revision: revision,
  });
  if (frozen.status !== "FROZEN") fail("Profile did not freeze through the real PostgREST path");
  return draft.profileVersionId;
}

function assertClosedResult(value, profileId, programId) {
  const keys = [
    "evalId", "inputFingerprint", "profileId", "programId", "requirements",
    "resultFingerprint", "rootTruth", "schemaVersion", "status",
  ];
  if (JSON.stringify(Object.keys(value ?? {}).sort()) !== JSON.stringify(keys)
      || value.schemaVersion !== "ELIGIBILITY_PRODUCTION_ASSEMBLY_V026"
      || value.profileId !== profileId
      || value.programId !== programId
      || !uuidPattern.test(value.evalId ?? "")
      || !/^[a-f0-9]{64}$/.test(value.inputFingerprint ?? "")
      || !/^[a-f0-9]{64}$/.test(value.resultFingerprint ?? "")
      || !Array.isArray(value.requirements)) {
    fail("M026 PostgREST result escaped its closed DTO");
  }
}

const status = readLocalStatus();
const apiUrl = localUrl(process.env.PHASE026_SUPABASE_URL ?? status.API_URL);
const anonKey = process.env.PHASE026_ANON_KEY ?? status.ANON_KEY;
const jwtSecret = process.env.PHASE026_JWT_SECRET ?? status.JWT_SECRET;
if (!anonKey || !jwtSecret) fail("Local Supabase status is missing test credentials");

const authUserIds = [];
let resetRequired = false;
try {
  const alice = await signUp(apiUrl, anonKey, "alice");
  const bob = await signUp(apiUrl, anonKey, "bob");
  authUserIds.push(alice.id, bob.id);
  const aliceProfile = await frozenProfile(apiUrl, anonKey, alice);
  const bobProfile = await frozenProfile(apiUrl, anonKey, bob);
  const fixture = installFixture(aliceProfile);
  resetRequired = true;
  const operationId = randomUUID();
  const request = {
    p_profile_version_id: aliceProfile,
    p_program_version_id: fixture.programVersionId,
    p_operation_id: operationId,
  };
  const [result, concurrentReplay] = await Promise.all([
    rpc(apiUrl, anonKey, alice.token, "assemble_eligibility_evaluation_v026", request),
    rpc(apiUrl, anonKey, alice.token, "assemble_eligibility_evaluation_v026", request),
  ]);
  assertClosedResult(result, aliceProfile, fixture.programVersionId);
  if (JSON.stringify(concurrentReplay) !== JSON.stringify(result)) fail("M026 concurrent exact retry did not converge");
  const replay = await rpc(apiUrl, anonKey, alice.token, "assemble_eligibility_evaluation_v026", request);
  if (JSON.stringify(replay) !== JSON.stringify(result)) fail("M026 PostgREST exact retry did not converge");
  if (database(`select count(*) from private.eligibility_assembly_operations_v026 where operation_id = '${operationId}'::uuid;`) !== "1") fail("M026 exact retry created duplicate state");

  const independentOperationIds = [randomUUID(), randomUUID()];
  const independent = await Promise.all(independentOperationIds.map((p_operation_id) =>
    rpc(apiUrl, anonKey, alice.token, "assemble_eligibility_evaluation_v026", {
      p_profile_version_id: aliceProfile,
      p_program_version_id: fixture.programVersionId,
      p_operation_id,
    })
  ));
  independent.forEach((value) => assertClosedResult(value, aliceProfile, fixture.programVersionId));
  if (independent[0].evalId === independent[1].evalId
      || independent.some((value) => value.evalId === result.evalId)) {
    fail("M026 independent operations did not create independent evaluations");
  }
  if (database(`select count(*) from private.eligibility_assembly_operations_v026 where operation_id in ('${independentOperationIds[0]}'::uuid, '${independentOperationIds[1]}'::uuid);`) !== "2") {
    fail("M026 independent concurrent operations lost durable identities");
  }

  const conflict = await rpc(apiUrl, anonKey, alice.token, "assemble_eligibility_evaluation_v026", {
    p_profile_version_id: aliceProfile,
    p_program_version_id: randomUUID(),
    p_operation_id: operationId,
  }, [400]);
  if (conflict?.message !== "ELIGIBILITY_ASSEMBLY_CONFLICT") fail("Changed-input retry was not rejected stably");

  const foreign = await rpc(apiUrl, anonKey, bob.token, "assemble_eligibility_evaluation_v026", {
    p_profile_version_id: aliceProfile,
    p_program_version_id: fixture.programVersionId,
    p_operation_id: randomUUID(),
  }, [400, 404]);
  if (foreign?.message !== "PROFILE_NOT_FOUND") fail("Unrelated user did not converge on PROFILE_NOT_FOUND");
  const missing = await rpc(apiUrl, anonKey, alice.token, "assemble_eligibility_evaluation_v026", {
    p_profile_version_id: randomUUID(),
    p_program_version_id: fixture.programVersionId,
    p_operation_id: randomUUID(),
  }, [400, 404]);
  if (missing?.message !== foreign?.message) fail("Missing and foreign Profiles were distinguishable");

  await rpc(apiUrl, anonKey, alice.token, "assemble_eligibility_evaluation_v026", {
    ...request,
    p_student_id: alice.id,
  }, [400, 404]);

  const draft = await rpc(apiUrl, anonKey, bob.token, "create_or_resume_profile_draft_v019", { p_operation_id: randomUUID() });
  const notFrozen = await rpc(apiUrl, anonKey, bob.token, "assemble_eligibility_evaluation_v026", {
    p_profile_version_id: draft.profileVersionId,
    p_program_version_id: fixture.programVersionId,
    p_operation_id: randomUUID(),
  }, [400]);
  if (notFrozen?.message !== "PROFILE_NOT_FROZEN") fail("DRAFT Profile was not rejected with a stable error");

  await rpc(apiUrl, anonKey, null, "assemble_eligibility_evaluation_v026", request, [401, 403]);
  await rpc(apiUrl, anonKey, expiredJwt(jwtSecret, alice.id), "assemble_eligibility_evaluation_v026", request, [401]);
  await rpc(apiUrl, anonKey, "malformed.jwt.value", "assemble_eligibility_evaluation_v026", request, [401]);
  console.log("Phase 026 real local Auth/JWT/PostgREST production assembly E2E: PASS");
} finally {
  if (resetRequired || authUserIds.length > 0) {
    command(process.env.SUPABASE_BIN ?? "supabase", ["db", "reset", "--local"]);
  }
}
