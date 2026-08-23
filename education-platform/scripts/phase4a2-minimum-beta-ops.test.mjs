import assert from "node:assert/strict";
import test from "node:test";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  DATABASE_CHECK_CODES,
  DEFAULT_EXPECTED_IDENTITY,
  EXPECTED_FUNCTIONS,
  OperationalCheckError,
  parseArgs,
  runOperationalCheck,
  validateReadOnlySqlPack,
} from "./phase4a2-minimum-beta-ops.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const sqlPackPath = resolve(here, "../supabase/snippets/phase4a2_minimum_beta_invariants.sql");
const projectRef = "abcdefghijklmnopqrst";
const token = "secret-access-token-never-print";

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function validContractCounts(count = 4) {
  return {
    event_count: count,
    exact_key_count: count,
    valid_request_id_count: count,
    valid_endpoint_count: count,
    expected_semantic_release_count: count,
    expected_build_count: count,
    expected_boundary_count: count,
    expected_stage_count: count,
    valid_status_count: count,
    valid_status_class_count: count,
    bounded_duration_count: count,
    valid_error_code_count: count,
  };
}

function applicationRows(overrides = {}) {
  return [
    {
      endpoint: "FIT_EVALUATE",
      semantic_release: DEFAULT_EXPECTED_IDENTITY.semanticRelease,
      deployed_build: DEFAULT_EXPECTED_IDENTITY.deployedBuild,
      boundary_version: DEFAULT_EXPECTED_IDENTITY.boundaryVersion,
      status: 201,
      status_class: "2xx",
      error_code: "NONE",
      cold_start: true,
      event_count: 1,
      ...overrides,
    },
    ...["FIT_NORMALIZATION_PREPARE", "FIT_NORMALIZATION_REVIEW", "FIT_NORMALIZATION_RESUME"].map(
      (endpoint) => ({
        endpoint,
        semantic_release: DEFAULT_EXPECTED_IDENTITY.semanticRelease,
        deployed_build: DEFAULT_EXPECTED_IDENTITY.deployedBuild,
        boundary_version: DEFAULT_EXPECTED_IDENTITY.boundaryVersion,
        status: 200,
        status_class: "2xx",
        error_code: "NONE",
        cold_start: false,
        event_count: 1,
      }),
    ),
  ];
}

function databaseRows(overrides = {}) {
  return DATABASE_CHECK_CODES.map((check_code) => ({
    check_code,
    violation_count: overrides[check_code] ?? 0,
  }));
}

function mockFetch({ appRows = applicationRows(), contract = validContractCounts(),
  gateway = [{ endpoint: "FIT_EVALUATE", status: 401, event_count: 2 }],
  dbRows = databaseRows(), mfaEnabled = true, deploymentVersion = 9,
  rawError = null } = {}) {
  const requests = [];
  const fetchImpl = async (input, init = {}) => {
    const url = new URL(input);
    requests.push({ url, init });
    assert.equal(init.headers.authorization, `Bearer ${token}`);
    if (rawError !== null) return jsonResponse(rawError, 500);
    if (url.pathname.endsWith("/functions")) {
      return jsonResponse(EXPECTED_FUNCTIONS.map((slug) => ({
        slug,
        status: "ACTIVE",
        version: deploymentVersion,
        verify_jwt: true,
        function_id: "11111111-1111-4111-8111-111111111111",
      })));
    }
    if (url.pathname === "/v1/projects") {
      return jsonResponse([{ ref: projectRef, organization_slug: "safe-org", name: "ignored" }]);
    }
    if (url.pathname === "/v1/organizations/safe-org/members") {
      return jsonResponse([{
        role_name: "Owner",
        mfa_enabled: mfaEnabled,
        email: "must-not-appear@example.test",
        user_name: "must-not-appear",
        user_id: "22222222-2222-4222-8222-222222222222",
      }]);
    }
    if (url.pathname.endsWith("/analytics/endpoints/logs")) {
      const sql = url.searchParams.get("sql");
      if (sql.includes("exact_key_count")) return jsonResponse({ error: null, result: [contract] });
      if (sql.includes("function_edge_logs")) return jsonResponse({ error: null, result: gateway });
      return jsonResponse({ error: null, result: appRows });
    }
    if (url.pathname.endsWith("/database/query/read-only")) {
      const body = JSON.parse(init.body);
      assert.equal(init.method, "POST");
      assert.equal(/\b(insert|update|delete|alter|drop|create)\b/i.test(body.query), false);
      assert.equal(body.query.toLowerCase().startsWith("with"), true);
      return jsonResponse(dbRows, 201);
    }
    throw new Error(`Unexpected URL ${url}`);
  };
  return { fetchImpl, requests };
}

async function run(options = {}) {
  const sql = await readFile(sqlPackPath, "utf8");
  const mocked = mockFetch(options);
  const result = await runOperationalCheck({
    projectRef,
    accessToken: token,
    includeDatabase: true,
    databaseSqlPack: sql,
    ownerConfigured: true,
    notificationChannelConfigured: true,
    fetchImpl: mocked.fetchImpl,
    apiBase: "https://api.example.test",
    now: () => new Date("2026-08-22T12:00:00.000Z"),
  });
  return { result, requests: mocked.requests };
}

test("checker emits only bounded aggregate/deployment/MFA/count results", async () => {
  const { result, requests } = await run();
  assert.equal(result.operationalCounts.boundaryEventCount, 4);
  assert.equal(result.operationalCounts.gateway401Count, 2);
  assert.equal(result.database.status, "RAN_VIA_SUPABASE_READ_ONLY_ENDPOINT");
  assert.equal(result.ownerMfa.status, "ENABLED");
  assert.equal(result.privacyDeletionIntegritySignal, "UNAVAILABLE");
  assert.deepEqual(result.blockers, ["PRIVACY_DELETION_INTEGRITY_SIGNAL_UNAVAILABLE"]);
  const serialized = JSON.stringify(result);
  for (const forbidden of [
    token,
    "must-not-appear@example.test",
    "must-not-appear",
    "11111111-1111-4111-8111-111111111111",
    "22222222-2222-4222-8222-222222222222",
  ]) assert.equal(serialized.includes(forbidden), false);
  assert.equal(requests.every(({ url }) => !url.toString().includes(token)), true);
});

test("MFA disabled is a private-beta blocker without exposing the member", async () => {
  const { result } = await run({ mfaEnabled: false });
  assert.equal(result.ownerMfa.status, "DISABLED");
  assert.equal(result.blockers.includes("OWNER_MFA_NOT_ENABLED"), true);
});

test("repeated 5xx, release skew, and database violations fail closed", async () => {
  const rows = applicationRows({
    deployed_build: "unexpected-build",
    status: 500,
    status_class: "5xx",
    error_code: "FIT_EVALUATION_FAILED_CLOSED",
    event_count: 5,
  });
  const contract = validContractCounts(8);
  const { result } = await run({
    appRows: rows,
    contract,
    dbRows: databaseRows({ FIT_STALE_BUILDING_GT_15M: 1 }),
  });
  assert.equal(result.blockers.includes("RELEASE_IDENTITY_MISMATCH"), true);
  assert.equal(result.blockers.includes("REPEATED_INTERNAL_5XX"), true);
  assert.equal(result.blockers.includes("STALE_BUILDING_PRESENT"), true);
});

test("unexpected dimensions are rejected instead of becoming telemetry labels", async () => {
  await assert.rejects(
    run({ appRows: applicationRows({ endpoint: "STUDENT_UUID_DIMENSION" }) }),
    (error) => error instanceof OperationalCheckError && error.code === "APPLICATION_DIMENSION_OUTSIDE_CATALOG",
  );
});

test("raw remote error text and nested secrets never enter the public checker error", async () => {
  const sql = await readFile(sqlPackPath, "utf8");
  const { fetchImpl } = mockFetch({ rawError: {
    message: "internal database secret",
    detail: "student UUID 33333333-3333-4333-8333-333333333333",
    stack: "private stack",
  } });
  await assert.rejects(
    runOperationalCheck({
      projectRef,
      accessToken: token,
      includeDatabase: true,
      databaseSqlPack: sql,
      fetchImpl,
      apiBase: "https://api.example.test",
    }),
    (error) => {
      assert.equal(error instanceof OperationalCheckError, true);
      assert.equal(error.code, "REMOTE_STATUS_REJECTED");
      assert.equal(error.message.includes("secret"), false);
      assert.equal(error.message.includes("33333333"), false);
      return true;
    },
  );
});

test("SQL pack validator rejects mutation, broad reads, and missing transaction guards", () => {
  for (const malicious of [
    "begin read only; -- PHASE4A2_COUNT_QUERY_BEGIN\nupdate public.fit_evaluations set evaluator_name='x';\n-- PHASE4A2_COUNT_QUERY_END\nrollback;",
    "begin read only; -- PHASE4A2_COUNT_QUERY_BEGIN\nselect * from public.fit_evaluations;\n-- PHASE4A2_COUNT_QUERY_END\nrollback;",
    "select 'FIT_STALE_BUILDING_GT_15M', 0;",
  ]) assert.throws(() => validateReadOnlySqlPack(malicious), OperationalCheckError);
});

test("CLI rejects unknown flags and never accepts an unbounded window", () => {
  assert.throws(() => parseArgs(["--project-ref", projectRef, "--window-minutes", "1441"]), OperationalCheckError);
  assert.throws(() => parseArgs(["--project-ref", projectRef, "--raw-rows"]), OperationalCheckError);
});
