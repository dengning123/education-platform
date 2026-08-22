import assert from "node:assert/strict";
import test from "node:test";
import {
  FIT_DIMENSIONS,
  FitContractError,
  canonicalFitInputJson,
  canonicalFitOutputJson,
  combineSignals,
  compareExactDecimal,
  deepFreeze,
  evaluateFit,
  type DecisionManifestItem,
  type FitEvaluationInput,
  type IntentAuthority,
} from "../src/index.js";
import {
  methodId,
  policies,
  ref,
  supplyDimension,
  unknownInput,
} from "./fixtures.js";

const preferred: IntentAuthority = {
  importance: "PREFERRED",
  basis: "STRUCTURED_STUDENT_DECLARATION",
  importanceEvidenceManifestKey: null,
  confirmedByStudent: true,
};

function required(evidence: string): IntentAuthority {
  return {
    importance: "REQUIRED",
    basis: "STRUCTURED_STUDENT_DECLARATION",
    importanceEvidenceManifestKey: evidence,
    confirmedByStudent: true,
  };
}

test("all-unknown fixture emits exactly six categorical limiting decisions", () => {
  const output = evaluateFit(unknownInput());
  assert.deepEqual(Object.keys(output.dimensions), FIT_DIMENSIONS);
  for (const dimension of FIT_DIMENSIONS) {
    const decision = output.dimensions[dimension];
    assert.equal(decision.assessment, "UNKNOWN");
    assert.equal(decision.confidence, "LOW");
    assert.equal(decision.evidenceCoverage, "INSUFFICIENT");
    assert.ok(decision.reasons.length >= 1);
    assert.ok(decision.limitingInputs.length >= 1);
  }
  const serialized = canonicalFitOutputJson(output);
  for (const forbidden of [
    "eligibility",
    "competitiveness",
    "score",
    "weight",
    "rank",
    "probability",
    "recommendation",
  ]) {
    assert.equal(serialized.toLowerCase().includes(forbidden), false);
  }
});

test("canonical replay is insertion-order independent and does not mutate frozen input", () => {
  const original = unknownInput();
  const permuted: FitEvaluationInput = {
    ...original,
    manifest: [...original.manifest].reverse(),
    inputStates: [...original.inputStates].reverse(),
    resolvedContract: {
      ...original.resolvedContract,
      reasons: [...original.resolvedContract.reasons].reverse(),
      semanticSourceClasses: [...original.resolvedContract.semanticSourceClasses].reverse(),
    },
  };
  deepFreeze(permuted);
  const before = JSON.stringify(permuted);
  assert.equal(canonicalFitInputJson(original), canonicalFitInputJson(permuted));
  assert.equal(
    canonicalFitOutputJson(evaluateFit(original)),
    canonicalFitOutputJson(evaluateFit(permuted)),
  );
  assert.equal(JSON.stringify(permuted), before);
});

test("boolean-only signal precedence is exhaustive and rejects impossible shapes", () => {
  assert.equal(combineSignals({ hasMaterialSupport: false, hasMaterialContradiction: false, hasRequiredConstraintContradiction: false, hasQualifiedStrongAlignment: false, hasDirectionalBasis: false }), "UNKNOWN");
  assert.equal(combineSignals({ hasMaterialSupport: true, hasMaterialContradiction: false, hasRequiredConstraintContradiction: false, hasQualifiedStrongAlignment: false, hasDirectionalBasis: true }), "ALIGNMENT");
  assert.equal(combineSignals({ hasMaterialSupport: true, hasMaterialContradiction: true, hasRequiredConstraintContradiction: false, hasQualifiedStrongAlignment: false, hasDirectionalBasis: true }), "MIXED");
  assert.equal(combineSignals({ hasMaterialSupport: true, hasMaterialContradiction: true, hasRequiredConstraintContradiction: true, hasQualifiedStrongAlignment: false, hasDirectionalBasis: true }), "MISALIGNMENT");
  assert.equal(combineSignals({ hasMaterialSupport: true, hasMaterialContradiction: false, hasRequiredConstraintContradiction: false, hasQualifiedStrongAlignment: true, hasDirectionalBasis: true }), "STRONG_ALIGNMENT");
  assert.throws(() => combineSignals({ hasMaterialSupport: false, hasMaterialContradiction: false, hasRequiredConstraintContradiction: false, hasQualifiedStrongAlignment: true, hasDirectionalBasis: true }));
});

test("Academic direct high-importance authoritative curriculum match is strong", () => {
  const policy = policies.ACADEMIC;
  const intent: DecisionManifestItem = {
    kind: "FIT_INTENT",
    ref: ref("ACADEMIC", policy.intentPolicy, "academic-intent", "academic-intent-source", "STUDENT_RAW_INTENT"),
    intent: { kind: "TAXONOMY_TARGET", intentId: "academic-intent-id", dimension: "ACADEMIC", authority: { ...preferred, importance: "STRONGLY_PREFERRED" }, conceptId: "quant-econ", relation: "DESIRED" },
  };
  const mappingRef = ref("ACADEMIC", policy.evidencePolicies[1]!, "academic-mapping", "course-source", "TAXONOMY_MAPPING");
  const mapping: DecisionManifestItem = { kind: "VERIFIED_MAPPING", ref: mappingRef, mappingKind: "CATALOG", relationRegistryId: "COURSE_EQUIVALENCY", relation: "COURSE_EQUIVALENCY", conceptId: "quant-econ", statusAtPin: "VERIFIED", reviewedAtAtPin: "2026-08-20T00:00:00.000Z", verificationEvidenceIdAtPin: "mapping-evidence", retiredAtAtPin: null };
  const course: DecisionManifestItem = { kind: "CANONICAL_PROGRAM_FACT", ref: ref("ACADEMIC", policy.evidencePolicies[0]!, "academic-course", "course-source", "PROGRAM_CANONICAL_FACT"), recordId: "course-1", knowledgeStatus: "KNOWN", selectedObservationId: "course-observation", fact: { recordType: "PROGRAM_COURSE", field: "course_name", value: "Quantitative Economics" } };
  const input = supplyDimension(unknownInput(), "ACADEMIC", [intent, mapping, course]);
  const decision = evaluateFit(input).dimensions.ACADEMIC;
  assert.equal(decision.assessment, "STRONG_ALIGNMENT");
  assert.equal(decision.confidence, "HIGH");
  assert.equal(decision.signals[0]?.signalCode, "DIRECT_HIGH_IMPORTANCE_AUTHORITATIVE_MATCH");
});

test("Career reviewed association remains bounded at MEDIUM confidence", () => {
  const policy = policies.CAREER;
  const intent: DecisionManifestItem = { kind: "FIT_INTENT", ref: ref("CAREER", policy.intentPolicy, "career-intent", "career-intent-source", "STUDENT_RAW_INTENT"), intent: { kind: "TAXONOMY_TARGET", intentId: "career-intent-id", dimension: "CAREER", authority: preferred, conceptId: "economist", relation: "DESIRED" } };
  const mapping: DecisionManifestItem = { kind: "VERIFIED_MAPPING", ref: ref("CAREER", policy.evidencePolicies[0]!, "career-mapping", "career-source", "TAXONOMY_MAPPING"), mappingKind: "CATALOG", relationRegistryId: "CAREER_ASSOCIATION", relation: "CAREER_ASSOCIATION", conceptId: "economist", statusAtPin: "VERIFIED", reviewedAtAtPin: "2026-08-20T00:00:00.000Z", verificationEvidenceIdAtPin: "career-evidence", retiredAtAtPin: null };
  const decision = evaluateFit(supplyDimension(unknownInput(), "CAREER", [intent, mapping])).dimensions.CAREER;
  assert.equal(decision.assessment, "ALIGNMENT");
  assert.equal(decision.confidence, "MEDIUM");
});

test("Financial intents remain independent and funding never erases a preferred-cost contradiction", () => {
  const policy = policies.FINANCIAL;
  const intentItems: DecisionManifestItem[] = [
    { kind: "FIT_INTENT", ref: ref("FINANCIAL", policy.intentPolicy, "hard-ceiling", "hard-ceiling-source", "STUDENT_RAW_INTENT"), intent: { kind: "FINANCIAL_CONSTRAINT", intentId: "hard", dimension: "FINANCIAL", authority: required("completeness-financial"), amount: "100.00", semantics: "HARD_TOTAL_COST_CEILING", currency: "USD", scope: "TOTAL_COST", period: "PROGRAM_DURATION", basis: "GROSS", components: ["TOTAL_COST"] } },
    { kind: "FIT_INTENT", ref: ref("FINANCIAL", policy.intentPolicy, "preferred-cost", "preferred-cost-source", "STUDENT_RAW_INTENT"), intent: { kind: "FINANCIAL_CONSTRAINT", intentId: "preferred", dimension: "FINANCIAL", authority: preferred, amount: "80", semantics: "PREFERRED_TOTAL_COST", currency: "USD", scope: "TOTAL_COST", period: "PROGRAM_DURATION", basis: "GROSS", components: ["TOTAL_COST"] } },
    { kind: "FIT_INTENT", ref: ref("FINANCIAL", policy.intentPolicy, "funding", "funding-source", "STUDENT_RAW_INTENT"), intent: { kind: "FINANCIAL_CONSTRAINT", intentId: "funding", dimension: "FINANCIAL", authority: preferred, amount: "1000", semantics: "AVAILABLE_FUNDING", currency: "USD", scope: "TOTAL_COST", period: "PROGRAM_DURATION", basis: "GROSS", components: ["TOTAL_COST"] } },
  ];
  const costPolicy = policy.evidencePolicies[0]!;
  const comparable = (key: string, intentId: string): DecisionManifestItem => ({ kind: "DIRECT_FINANCIAL_COMPARABLE", ref: ref("FINANCIAL", costPolicy, key, `${key}-source`, "PROGRAM_CANONICAL_FACT"), sourcePinId: `${key}-pin`, financialContractVersion: "FINANCIAL_BILLING_BASIS_V014", financialConstraintIntentId: intentId, comparable: { amount: "90.000", currency: "USD", scope: "TOTAL_COST", period: "PROGRAM_DURATION", basis: "GROSS", components: ["TOTAL_COST"] } });
  const decision = evaluateFit(supplyDimension(unknownInput(), "FINANCIAL", [...intentItems, comparable("hard-cost", "hard"), comparable("preferred-cost-value", "preferred")])).dimensions.FINANCIAL;
  assert.equal(decision.assessment, "MIXED");
  assert.equal(decision.confidence, "HIGH");
  assert.equal(decision.signals.some((signal) => signal.intentManifestRef === "funding"), false);
});

test("Funding by itself is not a ceiling or contradiction", () => {
  const policy = policies.FINANCIAL;
  const funding: DecisionManifestItem = { kind: "FIT_INTENT", ref: ref("FINANCIAL", policy.intentPolicy, "funding-only", "funding-only-source", "STUDENT_RAW_INTENT"), intent: { kind: "FINANCIAL_CONSTRAINT", intentId: "funding-only-id", dimension: "FINANCIAL", authority: preferred, amount: "50000", semantics: "AVAILABLE_FUNDING", currency: "USD", scope: "TOTAL_COST", period: "PROGRAM_DURATION", basis: "GROSS", components: ["TOTAL_COST"] } };
  const placeholder: DecisionManifestItem = { kind: "CANONICAL_PROGRAM_FACT", ref: ref("FINANCIAL", policy.evidencePolicies[0]!, "cost-placeholder", "cost-placeholder-source", "PROGRAM_CANONICAL_FACT"), recordId: "cost", knowledgeStatus: "KNOWN", selectedObservationId: "cost-observation", fact: { recordType: "PROGRAM_COST", field: "billing_basis", value: "TOTAL_PROGRAM" } };
  const decision = evaluateFit(supplyDimension(unknownInput(), "FINANCIAL", [funding, placeholder])).dimensions.FINANCIAL;
  assert.equal(decision.assessment, "UNKNOWN");
  assert.equal(decision.signals.length, 0);
});

test("location intent without an authorized location fact is UNKNOWN/PARTIAL", () => {
  const policy = policies.GEOGRAPHIC_DELIVERY;
  const location: DecisionManifestItem = { kind: "FIT_INTENT", ref: ref("GEOGRAPHIC_DELIVERY", policy.intentPolicy, "location-intent", "location-source", "STUDENT_RAW_INTENT"), intent: { kind: "LOCATION_CONSTRAINT", intentId: "location", dimension: "GEOGRAPHIC_DELIVERY", authority: preferred, relation: "PREFERRED", countryCode: "US", regionCode: null, locality: "New York" } };
  const delivery: DecisionManifestItem = { kind: "FIT_INTENT", ref: ref("GEOGRAPHIC_DELIVERY", policy.intentPolicy, "delivery-intent", "delivery-intent-source", "STUDENT_RAW_INTENT"), intent: { kind: "DELIVERY_CONSTRAINT", intentId: "delivery", dimension: "GEOGRAPHIC_DELIVERY", authority: preferred, deliveryMode: "IN_PERSON", relation: "DESIRED" } };
  const fact: DecisionManifestItem = { kind: "CANONICAL_PROGRAM_FACT", ref: ref("GEOGRAPHIC_DELIVERY", policy.evidencePolicies[0]!, "delivery-fact", "delivery-fact-source", "PROGRAM_CANONICAL_FACT"), recordId: "program", knowledgeStatus: "KNOWN", selectedObservationId: "delivery-observation", fact: { recordType: "PROGRAM_VERSION", field: "delivery_mode", value: "IN_PERSON" } };
  const decision = evaluateFit(supplyDimension(unknownInput(), "GEOGRAPHIC_DELIVERY", [location, delivery, fact])).dimensions.GEOGRAPHIC_DELIVERY;
  assert.equal(decision.assessment, "UNKNOWN");
  assert.equal(decision.evidenceCoverage, "PARTIAL");
  assert.equal(decision.confidence, "LOW");
});

test("Personal Preference evaluates exact duration without importing delivery semantics", () => {
  const policy = policies.PERSONAL_PREFERENCE;
  const intent: DecisionManifestItem = { kind: "FIT_INTENT", ref: ref("PERSONAL_PREFERENCE", policy.intentPolicy, "duration-intent", "duration-intent-source", "STUDENT_RAW_INTENT"), intent: { kind: "DURATION_CONSTRAINT", intentId: "duration", dimension: "PERSONAL_PREFERENCE", authority: preferred, minimumMonths: "9", maximumMonths: "12" } };
  const fact: DecisionManifestItem = { kind: "CANONICAL_PROGRAM_FACT", ref: ref("PERSONAL_PREFERENCE", policy.evidencePolicies[0]!, "duration-fact", "duration-fact-source", "PROGRAM_CANONICAL_FACT"), recordId: "program", knowledgeStatus: "KNOWN", selectedObservationId: "duration-observation", fact: { recordType: "PROGRAM_VERSION", field: "duration_months", value: "10.0" } };
  const decision = evaluateFit(supplyDimension(unknownInput(), "PERSONAL_PREFERENCE", [intent, fact])).dimensions.PERSONAL_PREFERENCE;
  assert.equal(decision.assessment, "ALIGNMENT");
  assert.equal(decision.confidence, "HIGH");
});

test("International Accessibility requires current exact official regulatory applicability", () => {
  const policy = policies.INTERNATIONAL_ACCESSIBILITY;
  const intent: DecisionManifestItem = { kind: "FIT_INTENT", ref: ref("INTERNATIONAL_ACCESSIBILITY", policy.intentPolicy, "intl-intent", "intl-intent-source", "STUDENT_RAW_INTENT"), intent: { kind: "TAXONOMY_TARGET", intentId: "intl", dimension: "INTERNATIONAL_ACCESSIBILITY", authority: preferred, conceptId: "opt-path", relation: "DESIRED" } };
  const claim: DecisionManifestItem = { kind: "HISTORICAL_CONTEXT_SELECTION", ref: ref("INTERNATIONAL_ACCESSIBILITY", policy.evidencePolicies[0]!, "intl-claim", "intl-claim-source", "FIT_CONTEXT_REGULATORY"), claimId: "claim", selectionId: "selection", observationId: "observation", knowledgeStatus: "KNOWN", observationWorkflowStatusAtSelection: "VERIFIED", observationReviewedAtAtSelection: "2026-08-20T00:00:00.000Z", authority: "OFFICIAL_REGULATORY", validFrom: "2026-01-01T00:00:00.000Z", validTo: "2026-12-31T23:59:59.000Z", programVersionId: "program-version-v1", geographyCode: "US", jurisdictionCode: "US", pathCode: "OPT", value: { claimCode: "JURISDICTION_PATH_ACCESSIBILITY", accessible: true, restrictionCode: null } };
  const access: DecisionManifestItem = { kind: "STUDENT_ACCESS_CONTEXT", ref: ref("INTERNATIONAL_ACCESSIBILITY", policy.evidencePolicies[1]!, "intl-access", "intl-access-source", "STUDENT_RAW_ACCESS_CONTEXT"), citizenshipCountryCode: "CN", residenceCountryCode: "US", jurisdictionCode: "US", currentStatusCode: "F1", authorizationPathCode: "F1", targetPathCode: "OPT" };
  const mapping: DecisionManifestItem = { kind: "VERIFIED_MAPPING", ref: ref("INTERNATIONAL_ACCESSIBILITY", policy.evidencePolicies[2]!, "intl-mapping", "intl-mapping-source", "TAXONOMY_MAPPING"), mappingKind: "FIT_CONTEXT", relationRegistryId: "PROGRAM_ASSOCIATED_WITH_PATH", relation: "PROGRAM_ASSOCIATED_WITH_PATH", conceptId: "opt-path", statusAtPin: "VERIFIED", reviewedAtAtPin: "2026-08-20T00:00:00.000Z", verificationEvidenceIdAtPin: "intl-mapping-evidence", retiredAtAtPin: null };
  const decision = evaluateFit(supplyDimension(unknownInput(), "INTERNATIONAL_ACCESSIBILITY", [intent, claim, access, mapping])).dimensions.INTERNATIONAL_ACCESSIBILITY;
  assert.equal(decision.assessment, "ALIGNMENT");
  assert.equal(decision.confidence, "HIGH");
});

test("prohibited product fields, registry drift, and duplicate membership fail before evaluation", () => {
  const prohibited = { ...unknownInput(), eligibilityStatus: "ELIGIBLE" } as FitEvaluationInput;
  assert.throws(() => evaluateFit(prohibited), FitContractError);

  const base = unknownInput();
  const drift = {
    ...base,
    resolvedContract: {
      ...base.resolvedContract,
      methods: {
        ...base.resolvedContract.methods,
        ACADEMIC: {
          ...base.resolvedContract.methods.ACADEMIC,
          identity: { ...base.resolvedContract.methods.ACADEMIC.identity, code: "ACADEMIC_ALIGNMENT_V99" },
        },
      },
    },
  } as FitEvaluationInput;
  assert.throws(() => evaluateFit(drift), FitContractError);

  const duplicate = {
    ...base,
    manifest: [...base.manifest, base.manifest[0]!],
  };
  assert.throws(() => evaluateFit(duplicate), FitContractError);
});

test("closed DTOs reject extra fields, policy misbinding, and pre-v014 Financial witnesses", () => {
  const extra = { ...unknownInput(), mysteryContext: true } as FitEvaluationInput;
  assert.throws(() => evaluateFit(extra), FitContractError);

  const geo = policies.GEOGRAPHIC_DELIVERY;
  const misboundFact: DecisionManifestItem = {
    kind: "CANONICAL_PROGRAM_FACT",
    ref: ref(
      "GEOGRAPHIC_DELIVERY",
      geo.intentPolicy,
      "misbound-delivery",
      "misbound-delivery-source",
      "PROGRAM_CANONICAL_FACT",
    ),
    recordId: "program",
    knowledgeStatus: "KNOWN",
    selectedObservationId: "delivery-observation",
    fact: { recordType: "PROGRAM_VERSION", field: "delivery_mode", value: "IN_PERSON" },
  };
  const misbound = {
    ...unknownInput(),
    manifest: [...unknownInput().manifest, misboundFact],
    inputStates: unknownInput().inputStates.map((state) =>
      state.inputPolicyRegistryId === misboundFact.ref.inputPolicyRegistryId
        ? {
            ...state,
            availability: "INCLUDED" as const,
            manifestItemKeys: [misboundFact.ref.manifestItemKey],
            completenessManifestItemKey: null,
          }
        : state,
    ),
  };
  assert.throws(() => evaluateFit(misbound), FitContractError);

  const financial = policies.FINANCIAL;
  const intent: DecisionManifestItem = {
    kind: "FIT_INTENT",
    ref: ref("FINANCIAL", financial.intentPolicy, "v014-intent", "v014-intent-source", "STUDENT_RAW_INTENT"),
    intent: { kind: "FINANCIAL_CONSTRAINT", intentId: "v014", dimension: "FINANCIAL", authority: preferred, amount: "100", semantics: "PREFERRED_TOTAL_COST", currency: "USD", scope: "TOTAL_COST", period: "PROGRAM_DURATION", basis: "GROSS", components: ["TOTAL_COST"] },
  };
  const oldWitness = {
    kind: "DIRECT_FINANCIAL_COMPARABLE",
    ref: ref("FINANCIAL", financial.evidencePolicies[0]!, "old-witness", "old-witness-source", "PROGRAM_CANONICAL_FACT"),
    sourcePinId: "old-pin",
    financialContractVersion: "FINANCIAL_BILLING_BASIS_V013",
    financialConstraintIntentId: "v014",
    comparable: { amount: "90", currency: "USD", scope: "TOTAL_COST", period: "PROGRAM_DURATION", basis: "GROSS", components: ["TOTAL_COST"] },
  } as unknown as DecisionManifestItem;
  assert.throws(
    () => evaluateFit(supplyDimension(unknownInput(), "FINANCIAL", [intent, oldWitness])),
    FitContractError,
  );
});

test("exact decimal comparison never uses binary floating point", () => {
  assert.equal(compareExactDecimal("0.10", "0.1"), 0);
  assert.equal(compareExactDecimal("999999999999999999999.999", "1000000000000000000000"), -1);
  assert.equal(compareExactDecimal("-0.0001", "0"), -1);
});

test("method IDs survive input and output without aliasing", () => {
  const output = evaluateFit(unknownInput());
  for (const dimension of FIT_DIMENSIONS) {
    assert.equal(output.dimensions[dimension].methodRegistryId, methodId(dimension));
  }
});
