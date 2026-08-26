import { createHmac, randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function fail(message) { throw new Error(message); }
function command(bin, args, options = {}) {
  const result = spawnSync(bin, args, { encoding: "utf8", ...options });
  if (result.status !== 0) fail(`${bin} failed with status ${result.status ?? "unknown"}`);
  return result.stdout;
}
function localUrl(value) {
  const url = new URL(value);
  if (!["127.0.0.1", "localhost"].includes(url.hostname)) fail("M027 E2E must target disposable local Supabase");
  return url;
}
function status() {
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
    method: "POST", headers: { apikey: anonKey, "content-type": "application/json" },
    body: JSON.stringify({ email: `phase027-${label}-${randomUUID()}@test.invalid`, password: `Phase027-${randomUUID()}-Aa1!` }),
  }, [200]);
  if (!uuid.test(data?.user?.id ?? "") || !data?.access_token) fail("Local Auth did not issue a valid session");
  return { id: data.user.id, token: data.access_token };
}
async function rpc(apiUrl, anonKey, token, name, value, statuses = [200]) {
  const headers = { apikey: anonKey, "content-type": "application/json" };
  if (token) headers.authorization = `Bearer ${token}`;
  return jsonRequest(new URL(`/rest/v1/rpc/${name}`, apiUrl), {
    method: "POST", headers, body: JSON.stringify(value),
  }, statuses);
}
function container() {
  const value = process.env.PHASE027_DB_CONTAINER;
  if (!value || !/^supabase_db_[A-Za-z0-9_.-]+$/.test(value)) fail("Exact disposable PHASE027_DB_CONTAINER is required");
  return value;
}
function database(sql) {
  return command(process.env.DOCKER_BIN ?? "docker", [
    "exec", container(), "psql", "-U", "postgres", "-d", "postgres", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql,
  ]).trim();
}
function installFixture(profileVersionId) {
  const sql = readFileSync(new URL("../../apps/web/tests/real-local/profile-eligibility-fit.fixture.sql", import.meta.url), "utf8");
  const result = spawnSync(process.env.DOCKER_BIN ?? "docker", [
    "exec", "-i", container(), "psql", "-U", "postgres", "-d", "postgres", "-At",
    "-v", "ON_ERROR_STOP=1", "-v", `profile_version_id=${profileVersionId}`, "-f", "-",
  ], { encoding: "utf8", input: sql, maxBuffer: 4 * 1024 * 1024 });
  if (result.status !== 0) fail("M027 local Program fixture failed");
  const line = result.stdout.split("\n").map((entry) => entry.trim()).reverse().find((entry) => entry.startsWith("{"));
  if (!line) fail("M027 fixture identity missing");
  return JSON.parse(line);
}
async function frozenProfile(apiUrl, anonKey, user) {
  await rpc(apiUrl, anonKey, user.token, "bootstrap_profile_identity_v019", {});
  const draft = await rpc(apiUrl, anonKey, user.token, "create_or_resume_profile_draft_v019", { p_operation_id: randomUUID() });
  let revision = draft.revision;
  for (const domain of ["EDUCATION_HISTORY", "COURSE_HISTORY", "COURSE_MAPPING", "TEST_HISTORY", "EXPERIENCE_HISTORY", "SKILL_HISTORY", "PREFERENCES", "GOALS"]) {
    await rpc(apiUrl, anonKey, user.token, "mutate_profile_draft_v019", {
      p_profile_version_id: draft.profileVersionId, p_operation_id: randomUUID(), p_expected_revision: revision,
      p_command: "COMPLETENESS_UPSERT", p_payload: { educationContextId: null, domain, completeness: "COMPLETE", explanation: null },
    });
    revision += 1;
  }
  const frozen = await rpc(apiUrl, anonKey, user.token, "freeze_profile_draft_v019", {
    p_profile_version_id: draft.profileVersionId, p_operation_id: randomUUID(), p_expected_revision: revision,
  });
  if (frozen.status !== "FROZEN") fail("M027 prerequisite Profile did not freeze");
  return draft.profileVersionId;
}
function assertDocument(value, profileVersionId, statusValue) {
  const keys = ["accessContext", "declarations", "dimensions", "intentSetId", "profileVersionId", "revision", "schemaVersion", "snapshotHash", "status", "taxonomyRelease", "versionNumber"];
  if (JSON.stringify(Object.keys(value ?? {}).sort()) !== JSON.stringify(keys)
    || value.schemaVersion !== "FIT_INTENT_DOCUMENT_V027" || value.profileVersionId !== profileVersionId
    || value.status !== statusValue || !uuid.test(value.intentSetId ?? "") || value.dimensions?.length !== 6) {
    fail("M027 document escaped its closed DTO");
  }
}

const local = status();
const apiUrl = localUrl(process.env.PHASE027_SUPABASE_URL ?? local.API_URL);
const anonKey = process.env.PHASE027_ANON_KEY ?? local.ANON_KEY;
const jwtSecret = process.env.PHASE027_JWT_SECRET ?? local.JWT_SECRET;
if (!anonKey || !jwtSecret) fail("Local Supabase credentials unavailable");

let resetRequired = false;
try {
  const alice = await signUp(apiUrl, anonKey, "alice");
  const bob = await signUp(apiUrl, anonKey, "bob");
  resetRequired = true;
  const aliceProfile = await frozenProfile(apiUrl, anonKey, alice);
  await frozenProfile(apiUrl, anonKey, bob);
  const fixture = installFixture(aliceProfile);

  const createId = randomUUID();
  const createRequest = { p_profile_version_id: aliceProfile, p_operation_id: createId };
  const created = await rpc(apiUrl, anonKey, alice.token, "create_or_resume_fit_intent_draft_v027", createRequest);
  const replay = await rpc(apiUrl, anonKey, alice.token, "create_or_resume_fit_intent_draft_v027", createRequest);
  if (JSON.stringify(created) !== JSON.stringify(replay) || created.revision !== 0) fail("M027 create replay did not converge");
  const intentSetId = created.intentSetId;
  let document = await rpc(apiUrl, anonKey, alice.token, "get_fit_intent_document_v027", { p_intent_set_id: intentSetId });
  assertDocument(document, aliceProfile, "DRAFT");
  const discovery = await rpc(apiUrl, anonKey, alice.token, "discover_fit_intent_v027", { p_profile_version_id: aliceProfile });
  if (discovery.activeDraft?.intentSetId !== intentSetId) fail("M027 discovery did not resume its draft");

  const foreign = await rpc(apiUrl, anonKey, bob.token, "get_fit_intent_document_v027", { p_intent_set_id: intentSetId }, [500]);
  const missing = await rpc(apiUrl, anonKey, alice.token, "get_fit_intent_document_v027", { p_intent_set_id: randomUUID() }, [500]);
  if (foreign?.code !== "P0002" || missing?.code !== foreign.code
    || foreign?.message !== "FIT_INTENT_NOT_FOUND" || missing?.message !== foreign.message) {
    fail("M027 foreign/missing identities were distinguishable");
  }

  const mutationId = randomUUID();
  const deliveryRequest = {
    p_intent_set_id: intentSetId, p_operation_id: mutationId, p_expected_revision: 0, p_command: "DECLARATION_CREATE",
    p_payload: { declaration: { dimension: "GEOGRAPHIC_DELIVERY", semanticType: "DELIVERY_CONSTRAINT", importance: "REQUIRED", importanceConfirmedByStudent: true, typedValue: { deliveryMode: "ONLINE", relation: "DESIRED" } } },
  };
  const delivery = await rpc(apiUrl, anonKey, alice.token, "mutate_fit_intent_draft_v027", deliveryRequest);
  if (JSON.stringify(await rpc(apiUrl, anonKey, alice.token, "mutate_fit_intent_draft_v027", deliveryRequest)) !== JSON.stringify(delivery)) fail("M027 exact mutation replay did not converge");
  const changed = await rpc(apiUrl, anonKey, alice.token, "mutate_fit_intent_draft_v027", {
    ...deliveryRequest, p_payload: { declaration: { ...deliveryRequest.p_payload.declaration, typedValue: { deliveryMode: "HYBRID", relation: "DESIRED" } } },
  }, [409]);
  if (changed?.message !== "FIT_INTENT_OPERATION_CONFLICT") fail("M027 changed replay did not fail closed");
  let revision = 1;
  for (const dimension of ["ACADEMIC", "CAREER", "FINANCIAL", "PERSONAL_PREFERENCE", "INTERNATIONAL_ACCESSIBILITY"]) {
    await rpc(apiUrl, anonKey, alice.token, "mutate_fit_intent_draft_v027", {
      p_intent_set_id: intentSetId, p_operation_id: randomUUID(), p_expected_revision: revision,
      p_command: "DIMENSION_MARK_NOT_SUPPLIED", p_payload: { dimension },
    });
    revision += 1;
  }
  const stale = await rpc(apiUrl, anonKey, alice.token, "mutate_fit_intent_draft_v027", {
    p_intent_set_id: intentSetId, p_operation_id: randomUUID(), p_expected_revision: 0,
    p_command: "DIMENSION_MARK_NOT_SUPPLIED", p_payload: { dimension: "ACADEMIC" },
  }, [400]);
  if (stale?.message !== "FIT_INTENT_REVISION_CONFLICT") fail("M027 stale revision did not fail closed");

  const freezeId = randomUUID();
  const freezeRequest = { p_intent_set_id: intentSetId, p_operation_id: freezeId, p_expected_revision: revision };
  const frozen = await rpc(apiUrl, anonKey, alice.token, "freeze_fit_intent_draft_v027", freezeRequest);
  if (JSON.stringify(await rpc(apiUrl, anonKey, alice.token, "freeze_fit_intent_draft_v027", freezeRequest)) !== JSON.stringify(frozen)) fail("M027 freeze replay did not converge");
  document = await rpc(apiUrl, anonKey, alice.token, "get_fit_intent_document_v027", { p_intent_set_id: intentSetId });
  assertDocument(document, aliceProfile, "FROZEN");
  if (!/^[a-f0-9]{64}$/.test(document.snapshotHash ?? "")) fail("M027 frozen snapshot hash missing");
  const immutable = await rpc(apiUrl, anonKey, alice.token, "mutate_fit_intent_draft_v027", {
    p_intent_set_id: intentSetId, p_operation_id: randomUUID(), p_expected_revision: frozen.revision,
    p_command: "DIMENSION_MARK_NOT_SUPPLIED", p_payload: { dimension: "ACADEMIC" },
  }, [500]);
  if (immutable?.message !== "FIT_INTENT_DRAFT_REQUIRED") fail("M027 frozen intent remained mutable");

  const assembly = await rpc(apiUrl, anonKey, alice.token, "get_fit_evaluation_assembly_v027", {
    p_profile_version_id: aliceProfile, p_intent_set_id: intentSetId, p_program_version_id: fixture.programVersionId,
  });
  if (assembly?.schemaVersion !== "FIT_EVALUATION_ASSEMBLY_V027" || assembly.intentSnapshotHash !== document.snapshotHash || assembly.dimensions?.length !== 6) fail("M027 authoritative assembly failed");
  await rpc(apiUrl, anonKey, bob.token, "get_fit_evaluation_assembly_v027", {
    p_profile_version_id: aliceProfile, p_intent_set_id: intentSetId, p_program_version_id: fixture.programVersionId,
  }, [500]);
  await rpc(apiUrl, anonKey, alice.token, "get_fit_intent_document_v027", { p_intent_set_id: intentSetId, p_student_id: alice.id }, [400, 404]);
  await rpc(apiUrl, anonKey, null, "get_fit_intent_document_v027", { p_intent_set_id: intentSetId }, [401, 403]);
  await rpc(apiUrl, anonKey, expiredJwt(jwtSecret, alice.id), "get_fit_intent_document_v027", { p_intent_set_id: intentSetId }, [401]);
  await rpc(apiUrl, anonKey, "malformed.jwt.value", "get_fit_intent_document_v027", { p_intent_set_id: intentSetId }, [401]);
  if (Number(database(`select count(*) from private.fit_intent_operations_v027 where student_id = (select student_id from private.student_identities where auth_user_id = '${alice.id}'::uuid);`)) < 1) fail("M027 idempotency state was not durable");
  console.log("Phase 027 real local Auth/JWT/PostgREST Intent lifecycle and assembly E2E: PASS");
} finally {
  if (resetRequired) command(process.env.SUPABASE_BIN ?? "supabase", ["db", "reset", "--local"]);
}
