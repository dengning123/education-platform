import { createHmac, randomUUID } from "node:crypto";
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
  if (!["127.0.0.1", "localhost"].includes(url.hostname)) fail(`${label} must target the disposable local Supabase stack`);
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

async function jsonRequest(url, init, expectedStatuses) {
  const response = await fetch(url, init);
  if (!expectedStatuses.includes(response.status)) fail(`Unexpected local HTTP status ${response.status}`);
  const text = await response.text();
  if (!text) return null;
  try { return JSON.parse(text); } catch { fail("Local endpoint returned malformed JSON"); }
}

async function signUp(apiUrl, anonKey, label) {
  const data = await jsonRequest(new URL("/auth/v1/signup", apiUrl), {
    method: "POST",
    headers: { apikey: anonKey, "content-type": "application/json" },
    body: JSON.stringify({
      email: `phase025-${label}-${randomUUID()}@test.invalid`,
      password: `Phase025-${randomUUID()}-Aa1!`,
    }),
  }, [200]);
  if (!uuidPattern.test(data?.user?.id ?? "") || !data?.access_token) fail("Local Auth did not issue a valid subject and session");
  return { id: data.user.id, token: data.access_token };
}

async function rpc(apiUrl, anonKey, token, name, body, statuses = [200]) {
  const headers = { apikey: anonKey, "content-type": "application/json" };
  if (token) headers.authorization = `Bearer ${token}`;
  return jsonRequest(new URL(`/rest/v1/rpc/${name}`, apiUrl), {
    method: "POST", headers, body: JSON.stringify(body),
  }, statuses);
}

function databaseCommand(sql, options = {}) {
  const container = process.env.PHASE025_DB_CONTAINER;
  if (!container || !/^supabase_db_[A-Za-z0-9_.-]+$/.test(container)) fail("Set the exact disposable PHASE025_DB_CONTAINER name");
  return command(process.env.DOCKER_BIN ?? "docker", [
    "exec", container, "psql", "-U", "postgres", "-d", "postgres",
    "-At", "-v", "ON_ERROR_STOP=1", "-c", sql,
  ], options);
}

function studentId(authUserId) {
  const value = databaseCommand(`select student_id from private.student_identities where auth_user_id = '${authUserId}'::uuid;`).trim();
  if (!uuidPattern.test(value)) fail("Auth subject did not bind to exactly one student");
  return value;
}

function cleanup(authUserIds) {
  const ids = authUserIds.filter((value) => uuidPattern.test(value));
  if (ids.length === 0) return;
  const list = ids.map((value) => `'${value}'::uuid`).join(",");
  databaseCommand(`
    do $cleanup$
    declare v_student_id uuid;
    begin
      for v_student_id in select student_id from private.student_identities where auth_user_id in (${list})
      loop
        perform public.delete_student_data(v_student_id, 'PHASE025_LOCAL_AUTH_POSTGREST_E2E_CLEANUP');
      end loop;
      delete from auth.users where id in (${list});
    end
    $cleanup$;
  `, { stdio: "ignore" });
}

function assertDiscovery(value, expectedProfileId, expectedVersion) {
  const keys = ["frozenAt", "profileVersionId", "schemaVersion", "status", "versionNumber"];
  if (
    JSON.stringify(Object.keys(value ?? {}).sort()) !== JSON.stringify(keys)
    || value.schemaVersion !== "PROFILE_FROZEN_DISCOVERY_V025"
    || value.profileVersionId !== expectedProfileId
    || value.versionNumber !== expectedVersion
    || value.status !== "FROZEN"
  ) fail("Latest-FROZEN discovery escaped its closed deterministic DTO");
}

const status = readLocalStatus();
const apiUrl = localUrl(process.env.PHASE025_SUPABASE_URL ?? status.API_URL, "Supabase API URL");
const anonKey = process.env.PHASE025_ANON_KEY ?? status.ANON_KEY;
const jwtSecret = process.env.PHASE025_JWT_SECRET ?? status.JWT_SECRET;
if (!anonKey || !jwtSecret) fail("Local Supabase status is missing required test credentials");

const authUserIds = [];
try {
  const alice = await signUp(apiUrl, anonKey, "alice");
  const bob = await signUp(apiUrl, anonKey, "bob");
  authUserIds.push(alice.id, bob.id);

  await rpc(apiUrl, anonKey, alice.token, "bootstrap_profile_identity_v019", {});
  await rpc(apiUrl, anonKey, bob.token, "bootstrap_profile_identity_v019", {});
  const aliceStudent = studentId(alice.id);
  const bobStudent = studentId(bob.id);
  const aliceOld = randomUUID();
  const aliceLatest = randomUUID();
  const bobLatest = randomUUID();

  const empty = await rpc(apiUrl, anonKey, alice.token, "get_latest_frozen_profile_v025", {}, [404, 500]);
  if (empty?.code !== "P0002" || empty?.message !== "PROFILE_NOT_FOUND") fail("No-FROZEN discovery did not fail closed");

  databaseCommand(`
    insert into public.student_profile_versions
      (profile_version_id, student_id, version_number, status, snapshot_hash, frozen_at, product_managed, profile_revision)
    values
      ('${aliceOld}'::uuid, '${aliceStudent}'::uuid, 1, 'FROZEN', repeat('a', 64), '2026-08-20T00:00:00Z', true, 1),
      ('${aliceLatest}'::uuid, '${aliceStudent}'::uuid, 3, 'FROZEN', repeat('b', 64), '2026-08-22T00:00:00Z', true, 2),
      ('${bobLatest}'::uuid, '${bobStudent}'::uuid, 2, 'FROZEN', repeat('c', 64), '2026-08-21T00:00:00Z', true, 1);
  `);

  const aliceDiscovery = await rpc(apiUrl, anonKey, alice.token, "get_latest_frozen_profile_v025", {});
  const bobDiscovery = await rpc(apiUrl, anonKey, bob.token, "get_latest_frozen_profile_v025", {});
  assertDiscovery(aliceDiscovery, aliceLatest, 3);
  assertDiscovery(bobDiscovery, bobLatest, 2);

  const aliceFrozenBefore = await rpc(apiUrl, anonKey, alice.token, "get_profile_document_v019", { p_profile_version_id: aliceLatest });
  const bobFrozenBefore = await rpc(apiUrl, anonKey, bob.token, "get_profile_document_v019", { p_profile_version_id: bobLatest });
  if (aliceFrozenBefore.status !== "FROZEN" || bobFrozenBefore.status !== "FROZEN") fail("Known frozen document read was not authoritative");

  for (const [caller, foreignProfile] of [[alice, bobLatest], [bob, aliceLatest]]) {
    const read = await rpc(apiUrl, anonKey, caller.token, "get_profile_document_v019", { p_profile_version_id: foreignProfile }, [404, 500]);
    const fork = await rpc(apiUrl, anonKey, caller.token, "fork_frozen_profile_to_draft_v020", { p_source_profile_version_id: foreignProfile, p_operation_id: randomUUID() }, [404, 500]);
    if (read?.message !== "PROFILE_NOT_FOUND" || fork?.message !== "PROFILE_NOT_FOUND") fail("Cross-owner read/fork did not converge on not-found");
  }

  await rpc(apiUrl, anonKey, null, "get_latest_frozen_profile_v025", {}, [401, 403]);
  await rpc(apiUrl, anonKey, expiredJwt(jwtSecret, alice.id), "get_latest_frozen_profile_v025", {}, [401]);
  await rpc(apiUrl, anonKey, "malformed.jwt.value", "get_latest_frozen_profile_v025", {}, [401]);
  await rpc(apiUrl, anonKey, alice.token, "get_latest_frozen_profile_v025", { p_student_id: bobStudent }, [404]);

  const fork = await rpc(apiUrl, anonKey, alice.token, "fork_frozen_profile_to_draft_v020", {
    p_source_profile_version_id: aliceLatest,
    p_operation_id: randomUUID(),
  });
  if (fork.operation !== "FORK_FROZEN" || fork.status !== "DRAFT" || fork.sourceProfileVersionId !== aliceLatest) fail("Owner fork did not return the authoritative new draft");
  const currentDraft = await rpc(apiUrl, anonKey, alice.token, "get_profile_document_v019", { p_profile_version_id: null });
  if (currentDraft.profileVersionId !== fork.profileVersionId || currentDraft.status !== "DRAFT" || currentDraft.versionNumber !== 4) fail("Post-fork authoritative current draft read failed");
  const aliceFrozenAfter = await rpc(apiUrl, anonKey, alice.token, "get_profile_document_v019", { p_profile_version_id: aliceLatest });
  if (JSON.stringify(aliceFrozenAfter) !== JSON.stringify(aliceFrozenBefore)) fail("Fork changed the source frozen Profile");

  cleanup(authUserIds);
  const residue = databaseCommand(`
    select
      (select count(*) from auth.users where id in ('${alice.id}'::uuid, '${bob.id}'::uuid))
      + (select count(*) from private.student_identities where auth_user_id in ('${alice.id}'::uuid, '${bob.id}'::uuid));
  `).trim();
  if (residue !== "0") fail("Phase 025 local Auth/PostgREST fixture residue remains");
  authUserIds.length = 0;
  console.log("Phase 025 real local Auth/PostgREST lifecycle security E2E: PASS");
} finally {
  cleanup(authUserIds);
}
