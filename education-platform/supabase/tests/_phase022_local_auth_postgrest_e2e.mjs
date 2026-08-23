import { randomUUID } from "node:crypto";
import { spawnSync } from "node:child_process";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const exactProjectionKeys = ["concepts", "releaseCode", "releaseOrdinal", "schemaVersion"];
const exactConceptKeys = ["activeAtRelease", "canonicalKey", "conceptId", "conceptKind", "displayName"];

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
  if (!expectedStatuses.includes(response.status)) fail(`Unexpected local HTTP status ${response.status}`);
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
        email: `phase022-${label}-${randomUUID()}@test.invalid`,
        password: `Phase022-${randomUUID()}-Aa1!`,
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
  const databaseContainer = process.env.PHASE022_DB_CONTAINER;
  if (!databaseContainer || !/^supabase_db_[A-Za-z0-9_.-]+$/.test(databaseContainer)) {
    fail("Set PSQL_BIN or the exact disposable PHASE022_DB_CONTAINER name");
  }
  return command(
    process.env.DOCKER_BIN ?? "docker",
    ["exec", databaseContainer, "psql", "-U", "postgres", "-d", "postgres", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql],
    options,
  );
}

function seedReferencedConcept(profileVersionId) {
  if (!uuidPattern.test(profileVersionId)) fail("Invalid disposable Profile fixture identity");
  const output = databaseCommand(`
    with latest_release as (
      select release_code, release_ordinal
      from public.taxonomy_releases
      where status = 'VERIFIED'
      order by release_ordinal desc, release_code desc
      limit 1
    ), selected_concept as (
      select concept.concept_id, concept.canonical_key, concept.concept_kind,
        concept.display_name, release.release_code, release.release_ordinal
      from public.taxonomy_concepts concept
      cross join latest_release release
      where concept.concept_kind in ('FIELD', 'SUBFIELD')
        and concept.introduced_release_ordinal <= release.release_ordinal
        and (concept.retired_release_ordinal is null
          or concept.retired_release_ordinal > release.release_ordinal)
      order by concept.canonical_key, concept.concept_id
      limit 1
    ), evidence as (
      insert into public.student_evidence_items (
        profile_version_id, evidence_type, locator
      ) values (
        '${profileVersionId}'::uuid, 'SELF_REPORT', 'phase022-local-projection-source'
      ) returning student_evidence_id
    ), degree as (
      insert into public.student_degrees (
        profile_version_id, institution_name, degree_name, degree_level,
        degree_status, student_evidence_id
      ) select '${profileVersionId}'::uuid, 'Projection University',
        'Projection Degree', 'BACHELORS', 'COMPLETED', student_evidence_id
      from evidence
      returning student_degree_id
    ), mapping as (
      insert into public.student_record_concept_mappings (
        profile_version_id, record_type, student_record_id, concept_id,
        mapping_status, method
      ) select '${profileVersionId}'::uuid, 'DEGREE', degree.student_degree_id,
        selected_concept.concept_id, 'PROPOSED', 'HUMAN'
      from degree cross join selected_concept
      returning student_mapping_id
    )
    select jsonb_build_object(
      'conceptId', selected_concept.concept_id,
      'canonicalKey', selected_concept.canonical_key,
      'conceptKind', selected_concept.concept_kind,
      'displayName', selected_concept.display_name,
      'releaseCode', selected_concept.release_code,
      'releaseOrdinal', selected_concept.release_ordinal
    )::text
    from selected_concept cross join mapping;
  `).trim();
  if (!output) fail("Disposable taxonomy fixture did not select a concept");
  return JSON.parse(output);
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
          'PHASE022_LOCAL_AUTH_POSTGREST_E2E_CLEANUP'
        );
      end loop;
      delete from auth.users where id in (${list});
    end
    $cleanup$;
  `, { stdio: "ignore" });
}

const status = readLocalStatus();
const apiUrl = localUrl(process.env.PHASE022_SUPABASE_URL ?? status.API_URL, "Supabase API URL");
const databaseUrl = localUrl(process.env.PHASE022_DATABASE_URL ?? status.DB_URL, "Supabase database URL").toString();
const anonKey = process.env.PHASE022_ANON_KEY ?? status.ANON_KEY;
if (!anonKey) fail("Local Supabase status is missing the anonymous credential");

const authUserIds = [];
try {
  const owner = await signUp(apiUrl, anonKey, "owner");
  const other = await signUp(apiUrl, anonKey, "other");
  authUserIds.push(owner.id, other.id);

  await rpc(apiUrl, anonKey, owner.token, "bootstrap_profile_identity_v019", {});
  const ownerDraft = await rpc(apiUrl, anonKey, owner.token, "create_or_resume_profile_draft_v019", { p_operation_id: randomUUID() });
  if (!uuidPattern.test(ownerDraft?.profileVersionId ?? "")) fail("Owner Profile draft was not created");

  await rpc(apiUrl, anonKey, other.token, "bootstrap_profile_identity_v019", {});
  await rpc(apiUrl, anonKey, other.token, "create_or_resume_profile_draft_v019", { p_operation_id: randomUUID() });

  const expected = seedReferencedConcept(ownerDraft.profileVersionId);
  const projection = await rpc(
    apiUrl,
    anonKey,
    owner.token,
    "get_profile_taxonomy_projection_v022",
    { p_profile_version_id: ownerDraft.profileVersionId },
  );
  if (JSON.stringify(Object.keys(projection).sort()) !== JSON.stringify(exactProjectionKeys)) {
    fail("Projection escaped its closed top-level DTO");
  }
  if (projection.schemaVersion !== "PROFILE_TAXONOMY_PROJECTION_V022"
    || projection.releaseCode !== expected.releaseCode
    || projection.releaseOrdinal !== expected.releaseOrdinal
    || projection.concepts?.length !== 1) {
    fail("Projection did not use the highest VERIFIED release and referenced-only concept set");
  }
  const [concept] = projection.concepts;
  if (JSON.stringify(Object.keys(concept).sort()) !== JSON.stringify(exactConceptKeys)
    || concept.conceptId !== expected.conceptId
    || concept.canonicalKey !== expected.canonicalKey
    || concept.conceptKind !== expected.conceptKind
    || concept.displayName !== expected.displayName
    || concept.activeAtRelease !== true) {
    fail("Projection concept did not match the closed release-aware label contract");
  }

  const unrelated = await rpc(
    apiUrl,
    anonKey,
    other.token,
    "get_profile_taxonomy_projection_v022",
    { p_profile_version_id: ownerDraft.profileVersionId },
    [500],
  );
  if (unrelated?.code !== "P0002" || unrelated?.message !== "PROFILE_NOT_FOUND") {
    fail("Unrelated Auth subject escaped owner-scoped projection isolation");
  }
  await rpc(
    apiUrl,
    anonKey,
    null,
    "get_profile_taxonomy_projection_v022",
    { p_profile_version_id: ownerDraft.profileVersionId },
    [401, 403],
  );

  console.log("Phase 022 real local Auth/PostgREST taxonomy E2E: PASS");
} finally {
  cleanup(authUserIds);
}
