import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const packageDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repositoryDirectory = resolve(packageDirectory, "../..");
const supabaseWorkdir = process.env.SUPABASE_WORKDIR ?? repositoryDirectory;
const supabaseCli = process.env.SUPABASE_CLI ?? "supabase";
const dockerCli = process.env.DOCKER_CLI ?? "docker";
const config = readFileSync(resolve(repositoryDirectory, "supabase/config.toml"), "utf8");
const projectId = config.match(/^project_id\s*=\s*"([^"]+)"/m)?.[1];
assert.ok(projectId, "supabase/config.toml must declare project_id");
const databaseContainer = process.env.SUPABASE_DB_CONTAINER ?? `supabase_db_${projectId}`;
const fixturePath = resolve(repositoryDirectory, "supabase/tests/_phase016_api_fixture.sql");
const cleanupPath = resolve(repositoryDirectory, "supabase/tests/_phase016_api_cleanup.sql");
const directFinancialFixturePath = resolve(repositoryDirectory, "supabase/tests/_phase016_api_direct_financial_fixture.sql");
const normalizedFinancialFixturePath = resolve(repositoryDirectory, "supabase/tests/_phase017_api_financial_fixture.sql");
const containerFixturePath = "/tmp/phase016_api_fixture.sql";
const containerCleanupPath = "/tmp/phase016_api_cleanup.sql";
const containerDirectFinancialFixturePath = "/tmp/phase016_api_direct_financial_fixture.sql";
const containerNormalizedFinancialFixturePath = "/tmp/phase017_api_financial_fixture.sql";
const studentId = "61600000-0000-0000-0000-000000000001";
const directFinancial = process.env.FIT_INTEGRATION_DIRECT_FINANCIAL === "1";
const normalizedContradiction = process.env.FIT_INTEGRATION_NORMALIZED_CONTRADICTION === "1";
const normalizedNet = process.env.FIT_INTEGRATION_NORMALIZED_NET === "1";
const normalizedFinancial = process.env.FIT_INTEGRATION_NORMALIZED_FINANCIAL === "1" || normalizedContradiction || normalizedNet;
assert.equal(directFinancial && normalizedFinancial, false, "direct and normalized Financial modes are mutually exclusive");
const preserveFixtureOnFailure = process.env.FIT_INTEGRATION_PRESERVE_ON_FAILURE === "1";
let passed = false;

function run(command, args, options = {}) {
  return execFileSync(command, args, {
    cwd: repositoryDirectory,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    ...options,
  });
}

function copySql(localPath, containerPath) {
  run(dockerCli, ["cp", localPath, `${databaseContainer}:${containerPath}`]);
}

function runSql(containerPath, variables = {}) {
  const variableArgs = Object.entries(variables).flatMap(([key, value]) => ["-v", `${key}=${value}`]);
  return run(dockerCli, [
    "exec", databaseContainer, "psql", "-X", "-v", "ON_ERROR_STOP=1",
    ...variableArgs, "-U", "postgres", "-d", "postgres", "-f", containerPath,
  ]);
}

async function responseJson(response) {
  const body = await response.text();
  if (body.length === 0) return null;
  try {
    return JSON.parse(body);
  } catch {
    return { rawBody: body };
  }
}

const status = JSON.parse(run(supabaseCli, ["status", "-o", "json"], { cwd: supabaseWorkdir }));
const email = `fit-phase016-${Date.now()}@example.test`;
const password = `Local-only-${crypto.randomUUID()}-Aa1!`;
let authUserId = null;
let accessToken = null;
let reviewerAuthUserId = null;
let reviewerAccessToken = null;

copySql(cleanupPath, containerCleanupPath);
try {
  runSql(containerCleanupPath);
} catch {
  // A missing prior fixture is the normal first-run state.
}

try {
  const signupResponse = await fetch(`${status.API_URL}/auth/v1/signup`, {
    method: "POST",
    headers: { apikey: status.ANON_KEY, "content-type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  const signup = await responseJson(signupResponse);
  assert.equal(signupResponse.ok, true, JSON.stringify(signup));
  authUserId = signup?.user?.id ?? null;
  accessToken = signup?.access_token ?? null;
  assert.match(authUserId ?? "", /^[0-9a-f-]{36}$/);
  assert.ok(accessToken, "local Auth signup must return an access token");

  copySql(fixturePath, containerFixturePath);
  runSql(containerFixturePath, { auth_user_id: authUserId, financial_basis: normalizedNet ? "NET_OF_VERIFIED_FUNDING" : "GROSS" });

  let directFinancialComparisons = [];
  if (directFinancial) {
    copySql(directFinancialFixturePath, containerDirectFinancialFixturePath);
    runSql(containerDirectFinancialFixturePath);
    const selected = run(dockerCli, [
      "exec", databaseContainer, "psql", "-X", "-A", "-t", "-F", "=",
      "-U", "postgres", "-d", "postgres", "-c",
      "select field_name,observation_id from public.canonical_field_selections where record_type='PROGRAM_COST' and record_id='00000000-0000-0000-0000-000000000404' and field_name in ('estimated_total_cost','billing_basis') order by field_name",
    ]).trim().split("\n").map((line) => line.split("="));
    const observationByField = new Map(selected.map(([field, id]) => [field, id]));
    assert.match(observationByField.get("estimated_total_cost") ?? "", /^[0-9a-f-]{36}$/);
    assert.match(observationByField.get("billing_basis") ?? "", /^[0-9a-f-]{36}$/);
    directFinancialComparisons = [{
      financialIntentId: "61600000-0000-0000-0000-000000000023",
      amountObservationId: observationByField.get("estimated_total_cost"),
      billingBasisObservationId: observationByField.get("billing_basis"),
    }];
  }

  let normalizedObservationByField = null;
  if (normalizedFinancial) {
    copySql(normalizedFinancialFixturePath, containerNormalizedFinancialFixturePath);
    runSql(containerNormalizedFinancialFixturePath, { annual_amount: normalizedNet || normalizedContradiction ? "50000" : "45000" });
    const selected = run(dockerCli, [
      "exec", databaseContainer, "psql", "-X", "-A", "-t", "-F", "=",
      "-U", "postgres", "-d", "postgres", "-c",
      "select field_name,observation_id from public.canonical_field_selections where record_type='PROGRAM_COST' and record_id='00000000-0000-0000-0000-000000000404' and field_name in ('estimated_total_cost','billing_basis') order by field_name",
    ]).trim().split("\n").map((line) => line.split("="));
    normalizedObservationByField = new Map(selected.map(([field, id]) => [field, id]));
    assert.match(normalizedObservationByField.get("estimated_total_cost") ?? "", /^[0-9a-f-]{36}$/);
    assert.match(normalizedObservationByField.get("billing_basis") ?? "", /^[0-9a-f-]{36}$/);

    const reviewerEmail = `fit-reviewer-${Date.now()}@example.test`;
    const reviewerPassword = `Local-reviewer-${crypto.randomUUID()}-Aa1!`;
    const reviewerSignupResponse = await fetch(`${status.API_URL}/auth/v1/signup`, {
      method: "POST",
      headers: { apikey: status.ANON_KEY, "content-type": "application/json" },
      body: JSON.stringify({ email: reviewerEmail, password: reviewerPassword }),
    });
    const reviewerSignup = await responseJson(reviewerSignupResponse);
    assert.equal(reviewerSignupResponse.ok, true, JSON.stringify(reviewerSignup));
    reviewerAuthUserId = reviewerSignup?.user?.id ?? null;
    assert.match(reviewerAuthUserId ?? "", /^[0-9a-f-]{36}$/);
    const reviewerUpdateResponse = await fetch(`${status.API_URL}/auth/v1/admin/users/${reviewerAuthUserId}`, {
      method: "PUT",
      headers: { apikey: status.SERVICE_ROLE_KEY, authorization: `Bearer ${status.SERVICE_ROLE_KEY}`, "content-type": "application/json" },
      body: JSON.stringify({ app_metadata: { fit_normalization_reviewer: true } }),
    });
    assert.equal(reviewerUpdateResponse.ok, true, JSON.stringify(await responseJson(reviewerUpdateResponse)));
    const reviewerTokenResponse = await fetch(`${status.API_URL}/auth/v1/token?grant_type=password`, {
      method: "POST",
      headers: { apikey: status.ANON_KEY, "content-type": "application/json" },
      body: JSON.stringify({ email: reviewerEmail, password: reviewerPassword }),
    });
    const reviewerTokenBody = await responseJson(reviewerTokenResponse);
    assert.equal(reviewerTokenResponse.ok, true, JSON.stringify(reviewerTokenBody));
    reviewerAccessToken = reviewerTokenBody?.access_token ?? null;
    assert.ok(reviewerAccessToken, "reviewer login must return a refreshed token with reviewer app_metadata");
  }

  const request = {
    profileVersionId: "61600000-0000-0000-0000-000000000002",
    intentSetId: "61600000-0000-0000-0000-000000000010",
    programVersionId: "00000000-0000-0000-0000-000000000401",
    taxonomyReleaseCode: "v0.1",
    supersedesEvaluationId: null,
    eligibilityContextEvaluationId: null,
    evidence: {
      canonicalObservationIds: [],
      catalogMappingIds: [],
      studentCourseIds: [],
      studentMappingIds: [],
      taxonomyConceptIds: [],
      contextClaimIds: [],
      contextMappingIds: [],
      accessContextId: null,
      directFinancialComparisons,
      approvedFinancialNormalizationIds: [],
    },
  };
  let response;
  if (normalizedFinancial) {
    const prepareResponse = await fetch(`${status.FUNCTIONS_URL}/fit-normalization-prepare`, {
      method: "POST",
      headers: { apikey: status.ANON_KEY, authorization: `Bearer ${accessToken}`, "content-type": "application/json" },
      body: JSON.stringify({
        evaluation: request,
        draft: {
          financialIntentId: "61600000-0000-0000-0000-000000000023",
          amountObservationId: normalizedObservationByField.get("estimated_total_cost"),
          billingBasisObservationId: normalizedObservationByField.get("billing_basis"),
          normalizationMethodCode: normalizedNet ? "ANNUAL_TO_NET_PROGRAM" : "ANNUAL_TO_PROGRAM",
          normalizationMethodVersion: 1,
          conversionEvidenceId: "00000000-0000-0000-0000-000000000705",
          academicYears: "2",
          rounding: "NONE",
          fundingIntentId: normalizedNet ? "61600000-0000-0000-0000-000000000027" : null,
        },
      }),
    });
    const prepared = await responseJson(prepareResponse);
    assert.equal(prepareResponse.status, 202, JSON.stringify(prepared));
    assert.match(prepared?.evaluationId ?? "", /^[0-9a-f-]{36}$/);
    assert.match(prepared?.normalizationId ?? "", /^[0-9a-f-]{36}$/);
    assert.equal(prepared?.reviewState, "DRAFT");

    const selfReviewResponse = await fetch(`${status.FUNCTIONS_URL}/fit-normalization-review`, {
      method: "POST",
      headers: { apikey: status.ANON_KEY, authorization: `Bearer ${accessToken}`, "content-type": "application/json" },
      body: JSON.stringify({ normalizationId: prepared.normalizationId, verificationEvidenceId: "30000000-0000-0000-0000-000000000173" }),
    });
    assert.equal(selfReviewResponse.status >= 400, true, JSON.stringify(await responseJson(selfReviewResponse)));

    const reviewResponse = await fetch(`${status.FUNCTIONS_URL}/fit-normalization-review`, {
      method: "POST",
      headers: { apikey: status.ANON_KEY, authorization: `Bearer ${reviewerAccessToken}`, "content-type": "application/json" },
      body: JSON.stringify({ normalizationId: prepared.normalizationId, verificationEvidenceId: "30000000-0000-0000-0000-000000000173" }),
    });
    const reviewed = await responseJson(reviewResponse);
    assert.equal(reviewResponse.status, 200, JSON.stringify(reviewed));
    assert.equal(reviewed?.reviewState, "VERIFIED");

    const resumeRequest = {
      evaluationId: prepared.evaluationId,
      normalizationId: prepared.normalizationId,
      evaluation: {
        ...request,
        evidence: { ...request.evidence, approvedFinancialNormalizationIds: [prepared.normalizationId] },
      },
    };
    response = await fetch(`${status.FUNCTIONS_URL}/fit-normalization-resume`, {
      method: "POST",
      headers: { apikey: status.ANON_KEY, authorization: `Bearer ${accessToken}`, "content-type": "application/json" },
      body: JSON.stringify(resumeRequest),
    });
  } else {
    response = await fetch(`${status.FUNCTIONS_URL}/fit-evaluate`, {
      method: "POST",
      headers: {
        apikey: status.ANON_KEY,
        authorization: `Bearer ${accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(request),
    });
  }
  const body = await responseJson(response);
  assert.equal(response.status, 201, JSON.stringify(body));
  assert.match(body?.evaluationId ?? "", /^[0-9a-f-]{36}$/);
  assert.match(body?.candidateInputFingerprint ?? "", /^[0-9a-f]{64}$/);
  assert.match(body?.resultFingerprint ?? "", /^[0-9a-f]{64}$/);
  assert.equal(body?.schemaVersion, "fit-v0.1");
  assert.deepEqual(Object.keys(body?.dimensions ?? {}).sort(), [
    "ACADEMIC",
    "CAREER",
    "FINANCIAL",
    "GEOGRAPHIC_DELIVERY",
    "INTERNATIONAL_ACCESSIBILITY",
    "PERSONAL_PREFERENCE",
  ]);
  for (const [name, dimension] of Object.entries(body.dimensions)) {
    if ((directFinancial || normalizedFinancial) && name === "FINANCIAL") {
      assert.equal(dimension.assessment, normalizedContradiction && name === "FINANCIAL" ? "MISALIGNMENT" : "ALIGNMENT");
      assert.equal(dimension.confidence, normalizedFinancial ? "MEDIUM" : "HIGH");
      assert.equal(dimension.evidenceCoverage, "SUFFICIENT");
    } else {
      assert.equal(dimension.assessment, "UNKNOWN");
      assert.equal(dimension.confidence, "LOW");
      assert.equal(dimension.evidenceCoverage, "INSUFFICIENT");
    }
  }
  const serialized = JSON.stringify(body).toLowerCase();
  for (const forbidden of ["score", "weight", "rank", "probability", "recommendation", "competitiveness", "eligibility"]) {
    assert.equal(serialized.includes(forbidden), false, `response contains prohibited ${forbidden} semantics`);
  }

  const persistedResponse = await fetch(
    `${status.REST_URL}/fit_evaluations?evaluation_id=eq.${body.evaluationId}&select=evaluation_state,candidate_input_fingerprint,result_fingerprint`,
    { headers: { apikey: status.SERVICE_ROLE_KEY, authorization: `Bearer ${status.SERVICE_ROLE_KEY}` } },
  );
  const persisted = await responseJson(persistedResponse);
  assert.equal(persistedResponse.ok, true, JSON.stringify(persisted));
  assert.deepEqual(persisted, [{
    evaluation_state: "COMPLETED",
    candidate_input_fingerprint: body.candidateInputFingerprint,
    result_fingerprint: body.resultFingerprint,
  }]);

  const resultResponse = await fetch(
    `${status.REST_URL}/fit_dimension_results?evaluation_id=eq.${body.evaluationId}&select=dimension,assessment,confidence,evidence_coverage`,
    { headers: { apikey: status.SERVICE_ROLE_KEY, authorization: `Bearer ${status.SERVICE_ROLE_KEY}` } },
  );
  const results = await responseJson(resultResponse);
  assert.equal(resultResponse.ok, true, JSON.stringify(results));
  assert.equal(results.length, 6);
  assert.ok(results.every((row) => (directFinancial || normalizedFinancial) && row.dimension === "FINANCIAL"
    ? row.assessment === (normalizedContradiction ? "MISALIGNMENT" : "ALIGNMENT") && row.confidence === (normalizedFinancial ? "MEDIUM" : "HIGH") && row.evidence_coverage === "SUFFICIENT"
    : row.assessment === "UNKNOWN" && row.confidence === "LOW" && row.evidence_coverage === "INSUFFICIENT"));

  process.stdout.write(JSON.stringify({
    status: "passed",
    evaluationId: body.evaluationId,
    dimensions: results.length,
    state: persisted[0].evaluation_state,
    directFinancial,
    normalizedFinancial,
    normalizedContradiction,
    normalizedNet,
  }) + "\n");
  passed = true;
} finally {
  if (passed || !preserveFixtureOnFailure) {
    try {
      runSql(containerCleanupPath);
    } catch (error) {
      process.stderr.write(`Fixture cleanup failed: ${error instanceof Error ? error.message : String(error)}\n`);
    }
    if (authUserId !== null) {
      try {
        await fetch(`${status.API_URL}/auth/v1/admin/users/${authUserId}`, {
          method: "DELETE",
          headers: {
            apikey: status.SERVICE_ROLE_KEY,
            authorization: `Bearer ${status.SERVICE_ROLE_KEY}`,
          },
        });
      } catch {
        // The database fixture has already removed the identity link.
      }
    }
    if (reviewerAuthUserId !== null) {
      try {
        await fetch(`${status.API_URL}/auth/v1/admin/users/${reviewerAuthUserId}`, {
          method: "DELETE",
          headers: { apikey: status.SERVICE_ROLE_KEY, authorization: `Bearer ${status.SERVICE_ROLE_KEY}` },
        });
      } catch {
        // The disposable local stack is destroyed after integration coverage.
      }
    }
  }
}
