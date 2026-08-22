import assert from "node:assert/strict";
import test from "node:test";
import {
  FitAdapterError,
  calculateReviewedFinancialNormalization,
  FitExecutorPostgrestGateway,
  FitSnapshotGateway,
  parseFitEvaluationResumeRequest,
  parseFitEvaluationRequest,
  parseFitFinancialNormalizationDraftRequest,
  parseFitFinancialNormalizationReviewRequest,
  PostgrestGateway,
  postgresIn,
  requireOne,
} from "../src/index.js";

const validRequest = {
  profileVersionId: "profile-1",
  intentSetId: "intent-1",
  programVersionId: "program-1",
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
    directFinancialComparisons: [],
    approvedFinancialNormalizationIds: [],
  },
};

test("request boundary accepts only the closed production DTO", () => {
  assert.deepEqual(parseFitEvaluationRequest(validRequest), validRequest);
  assert.throws(
    () => parseFitEvaluationRequest({ ...validRequest, score: 0.9 }),
    (error: unknown) => error instanceof FitAdapterError && error.status === 400,
  );
  assert.throws(
    () => parseFitEvaluationRequest({
      ...validRequest,
      evidence: {
        ...validRequest.evidence,
        canonicalObservationIds: ["observation-1", "observation-1"],
      },
    }),
    /duplicates/,
  );
});

test("request boundary permits at most one direct Financial source per intent", () => {
  const financial = {
    financialIntentId: "intent-financial",
    amountObservationId: "amount-1",
    billingBasisObservationId: "basis-1",
  };
  assert.throws(
    () => parseFitEvaluationRequest({
      ...validRequest,
      evidence: {
        ...validRequest.evidence,
        directFinancialComparisons: [financial, { ...financial, amountObservationId: "amount-2" }],
      },
    }),
    /Only one direct Financial comparison/,
  );
});

test("normalization workflow boundaries are closed and phase-specific", () => {
  const draft = parseFitFinancialNormalizationDraftRequest({
    evaluation: validRequest,
    draft: {
      financialIntentId: "intent-financial",
      amountObservationId: "amount-1",
      billingBasisObservationId: "basis-1",
      normalizationMethodCode: "ANNUAL_TO_PROGRAM",
      normalizationMethodVersion: 1,
      conversionEvidenceId: "evidence-1",
      academicYears: "2",
      rounding: "NONE",
      fundingIntentId: null,
    },
  });
  assert.equal(draft.draft.academicYears, "2");
  assert.throws(() => parseFitFinancialNormalizationDraftRequest({
    evaluation: validRequest,
    draft: { ...draft.draft, rounding: "HALF_UP" },
  }), /only exact no-rounding/);
  assert.throws(() => parseFitFinancialNormalizationDraftRequest({
    evaluation: validRequest,
    draft: { ...draft.draft, normalizationMethodCode: "ANNUAL_TO_NET_PROGRAM", fundingIntentId: null },
  }), /requires exactly one funding intent/);
  assert.deepEqual(parseFitFinancialNormalizationReviewRequest({
    normalizationId: "normalization-1",
    verificationEvidenceId: "review-evidence-1",
  }), {
    normalizationId: "normalization-1",
    verificationEvidenceId: "review-evidence-1",
  });
  const resumeEvaluation = {
    ...validRequest,
    evidence: { ...validRequest.evidence, approvedFinancialNormalizationIds: ["normalization-1"] },
  };
  assert.equal(parseFitEvaluationResumeRequest({
    evaluationId: "evaluation-1",
    normalizationId: "normalization-1",
    evaluation: resumeEvaluation,
  }).evaluationId, "evaluation-1");
  assert.throws(() => parseFitEvaluationResumeRequest({
    evaluationId: "evaluation-1",
    normalizationId: "normalization-2",
    evaluation: resumeEvaluation,
  }), /exactly the reviewed normalization/);
});

test("reviewed Financial arithmetic is exact and formula-closed", () => {
  assert.equal(calculateReviewedFinancialNormalization({
    formulaCode: "MULTIPLY_SOURCE_BY_ACADEMIC_YEARS",
    sourceAmount: "45000.25",
    academicYears: "2",
    fundingAmount: null,
    rounding: "NONE",
    sourceCurrency: "USD",
    targetCurrency: "USD",
  }), "90000.5");
  assert.equal(calculateReviewedFinancialNormalization({
    formulaCode: "MULTIPLY_SOURCE_BY_ACADEMIC_YEARS_THEN_SUBTRACT_FUNDING",
    sourceAmount: "50000",
    academicYears: "2",
    fundingAmount: "15000.01",
    rounding: "NONE",
    sourceCurrency: "USD",
    targetCurrency: "USD",
  }), "84999.99");
  assert.throws(() => calculateReviewedFinancialNormalization({
    formulaCode: "MULTIPLY_SOURCE_BY_ACADEMIC_YEARS",
    sourceAmount: "1",
    academicYears: "2",
    fundingAmount: null,
    rounding: "NONE",
    sourceCurrency: "USD",
    targetCurrency: "EUR",
  }), /does not authorize currency conversion/);
});

test("PostgREST gateway binds authorization and fails closed on database errors", async () => {
  const calls: Array<{ url: string; init: RequestInit }> = [];
  const fetchOk: typeof fetch = async (input, init = {}) => {
    calls.push({ url: String(input), init });
    return new Response('[{"id":"row-1"}]', { status: 200 });
  };
  const gateway = new PostgrestGateway("https://database.example/", "api-key", "user-token", fetchOk);
  assert.deepEqual(await gateway.select<{ id: string }>("records", { select: "id", id: "eq.row-1" }), [{ id: "row-1" }]);
  assert.equal(calls.length, 1);
  assert.match(calls[0]!.url, /\/rest\/v1\/records\?/);
  assert.equal(new Headers(calls[0]!.init.headers).get("authorization"), "Bearer user-token");
  assert.equal(new Headers(calls[0]!.init.headers).get("apikey"), "api-key");

  const fetchRejected: typeof fetch = async () => new Response(
    JSON.stringify({ message: "denied" }),
    { status: 403, headers: { "content-type": "application/json" } },
  );
  await assert.rejects(
    () => new PostgrestGateway("https://database.example", "key", "token", fetchRejected).rpc("private_rpc"),
    (error: unknown) => error instanceof FitAdapterError && error.status === 403 && error.message === "denied",
  );
});

test("database helpers reject ambiguous and unsafe identities", () => {
  assert.equal(requireOne(["only"], "fixture"), "only");
  assert.throws(() => requireOne([], "fixture"), /exactly one row/);
  assert.equal(postgresIn(["safe-id", "v0.1"]), "in.(safe-id,v0.1)");
  assert.throws(() => postgresIn(["unsafe,value"]), /Unsafe PostgREST filter value/);
});

test("executor gateway routes writes through frozen composite-insert RPCs", async () => {
  const paths: string[] = [];
  const fetchRpc: typeof fetch = async (input) => {
    paths.push(String(input));
    return new Response(null, { status: 204 });
  };
  const gateway = new FitExecutorPostgrestGateway("https://database.example", "service-key", "service-key", fetchRpc);
  const rows = await gateway.insert<Record<string, unknown>>("fit_manifest_items", [{ evaluation_id: "evaluation-1" }]);
  assert.match(String(rows[0]?.manifest_item_id), /^[0-9a-f-]{36}$/);
  assert.match(paths[0] ?? "", /\/rest\/v1\/rpc\/insert_fit_manifest_item$/);
  await assert.rejects(() => gateway.insert("fit_contract_releases", [{}]), /No frozen executor insert entry point/);
});

test("snapshot gateway exposes only bounded rows and closed filters", async () => {
  const gateway = new FitSnapshotGateway({
    records: [
      { id: "b", status: "ACTIVE", retired_at: null },
      { id: "a", status: "RETIRED", retired_at: "2026-01-01" },
    ],
  });
  assert.deepEqual(await gateway.select("records", { status: "eq.ACTIVE", retired_at: "is.null" }), [
    { id: "b", status: "ACTIVE", retired_at: null },
  ]);
  assert.deepEqual(await gateway.select("records", { id: "in.(a,b)", order: "id" }), [
    { id: "a", status: "RETIRED", retired_at: "2026-01-01" },
    { id: "b", status: "ACTIVE", retired_at: null },
  ]);
  assert.throws(() => gateway.select("unavailable"), /does not expose/);
});
