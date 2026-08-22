import {
  FIT_DIMENSIONS,
  type DecisionManifestItem,
  type FitDimension,
  type FitEvaluationInput,
  type FitIntent,
  type FitMethodCode,
  type ResolvedMethodContract,
} from "./contracts.js";

export class FitContractError extends Error {
  override readonly name = "FitContractError";
}

const METHOD_CONTRACT: Readonly<
  Record<
    FitDimension,
    Readonly<{
      code: FitMethodCode;
      inferenceCategory: "HYBRID" | "DETERMINISTIC";
      permitsStrongAlignment: boolean;
    }>
  >
> = {
  ACADEMIC: {
    code: "ACADEMIC_ALIGNMENT_V01",
    inferenceCategory: "HYBRID",
    permitsStrongAlignment: true,
  },
  CAREER: {
    code: "CAREER_ALIGNMENT_V01",
    inferenceCategory: "HYBRID",
    permitsStrongAlignment: false,
  },
  FINANCIAL: {
    code: "FINANCIAL_ALIGNMENT_V01",
    inferenceCategory: "DETERMINISTIC",
    permitsStrongAlignment: false,
  },
  GEOGRAPHIC_DELIVERY: {
    code: "GEOGRAPHIC_DELIVERY_ALIGNMENT_V01",
    inferenceCategory: "HYBRID",
    permitsStrongAlignment: false,
  },
  PERSONAL_PREFERENCE: {
    code: "PERSONAL_PREFERENCE_ALIGNMENT_V01",
    inferenceCategory: "HYBRID",
    permitsStrongAlignment: false,
  },
  INTERNATIONAL_ACCESSIBILITY: {
    code: "INTERNATIONAL_ACCESSIBILITY_V01",
    inferenceCategory: "HYBRID",
    permitsStrongAlignment: false,
  },
};

function fail(message: string): never {
  throw new FitContractError(message);
}

function requireValue(condition: boolean, message: string): asserts condition {
  if (!condition) fail(message);
}

function requireText(value: string, label: string): void {
  requireValue(value.trim().length > 0, `${label} is required`);
}

function requireIsoDate(value: string, label: string): void {
  requireText(value, label);
  requireValue(Number.isFinite(Date.parse(value)), `${label} must be an ISO timestamp`);
}

function assertExactKeys(
  value: object,
  expected: readonly string[],
  label: string,
): void {
  const actual = Object.keys(value).sort();
  const required = [...expected].sort();
  requireValue(
    actual.length === required.length &&
      actual.every((key, index) => key === required[index]),
    `${label} is not an exact closed object`,
  );
}

export function assertExactDecimal(value: string, label: string): void {
  requireValue(/^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$/.test(value), `${label} must be an exact decimal string`);
}

function assertUnique(values: readonly string[], label: string): void {
  const seen = new Set<string>();
  for (const value of values) {
    requireText(value, label);
    if (seen.has(value)) fail(`Duplicate ${label}: ${value}`);
    seen.add(value);
  }
}

function assertNoProhibitedDecisionKeys(value: unknown, path = "input"): void {
  if (Array.isArray(value)) {
    value.forEach((child, index) => assertNoProhibitedDecisionKeys(child, `${path}[${index}]`));
    return;
  }
  if (value === null || typeof value !== "object") return;
  for (const [key, child] of Object.entries(value)) {
    if (/(eligibility|competitiveness|admissionProbability|acceptanceLikelihood|recommendation|prestige|ranking|percentile|score|weight)/i.test(key)) {
      fail(`Prohibited decision field at ${path}.${key}`);
    }
    assertNoProhibitedDecisionKeys(child, `${path}.${key}`);
  }
}

function validateIntent(intent: FitIntent): void {
  const intentKeys: Readonly<Record<FitIntent["kind"], readonly string[]>> = {
    TAXONOMY_TARGET: ["kind", "intentId", "dimension", "authority", "conceptId", "relation"],
    LOCATION_CONSTRAINT: ["kind", "intentId", "dimension", "authority", "relation", "countryCode", "regionCode", "locality"],
    DELIVERY_CONSTRAINT: ["kind", "intentId", "dimension", "authority", "deliveryMode", "relation"],
    FINANCIAL_CONSTRAINT: ["kind", "intentId", "dimension", "authority", "amount", "semantics", "currency", "scope", "period", "basis", "components"],
    DURATION_CONSTRAINT: ["kind", "intentId", "dimension", "authority", "minimumMonths", "maximumMonths"],
    PROGRAM_FEATURE_CONSTRAINT: ["kind", "intentId", "dimension", "authority", "feature", "expected"],
  };
  assertExactKeys(intent, intentKeys[intent.kind], `${intent.kind} intent`);
  assertExactKeys(
    intent.authority,
    ["importance", "basis", "importanceEvidenceManifestKey", "confirmedByStudent"],
    "intent authority",
  );
  requireText(intent.intentId, "intentId");
  if (intent.authority.importance === "REQUIRED") {
    requireValue(intent.authority.confirmedByStudent, "REQUIRED intent must be confirmed by the student");
    requireValue(
      intent.authority.importanceEvidenceManifestKey !== null,
      "REQUIRED intent must carry importance evidence",
    );
  }
  if (intent.kind === "FINANCIAL_CONSTRAINT") {
    assertExactDecimal(intent.amount, "financial amount");
    assertUnique(intent.components, "financial component");
  }
  if (intent.kind === "DURATION_CONSTRAINT") {
    if (intent.minimumMonths !== null) assertExactDecimal(intent.minimumMonths, "minimumMonths");
    if (intent.maximumMonths !== null) assertExactDecimal(intent.maximumMonths, "maximumMonths");
    requireValue(
      intent.minimumMonths !== null || intent.maximumMonths !== null,
      "Duration intent requires at least one bound",
    );
  }
  if (intent.kind === "LOCATION_CONSTRAINT") {
    requireValue(
      intent.countryCode !== null || intent.regionCode !== null || intent.locality !== null,
      "Location intent requires an explicit location",
    );
  }
  if (intent.kind === "PROGRAM_FEATURE_CONSTRAINT") {
    const personal = new Set([
      "CAPSTONE_AVAILABLE",
      "RESEARCH_OPPORTUNITY",
      "FACULTY_ACCESS",
      "COHORT_STRUCTURE",
    ]);
    if (intent.dimension === "PERSONAL_PREFERENCE") {
      requireValue(personal.has(intent.feature), "Personal Preference received another dimension's semantics");
    } else {
      requireValue(
        intent.feature === "INTERNATIONAL_PATH_SUPPORT",
        "International Accessibility received Personal Preference semantics",
      );
    }
  }
}

function validateMethodContract(
  dimension: FitDimension,
  method: ResolvedMethodContract,
): void {
  const expected = METHOD_CONTRACT[dimension];
  requireValue(method.dimension === dimension, `Resolved method dimension drift for ${dimension}`);
  requireValue(method.identity.code === expected.code, `Resolved method code drift for ${dimension}`);
  requireValue(method.identity.version === "1", `Resolved method version drift for ${dimension}`);
  requireValue(
    method.inferenceCategory === expected.inferenceCategory,
    `Resolved inference category drift for ${dimension}`,
  );
  requireValue(
    method.permitsStrongAlignment === expected.permitsStrongAlignment,
    `Resolved strong-alignment permission drift for ${dimension}`,
  );
  requireValue(method.definitionState.status === "VERIFIED", `${dimension} method is not verified`);
  requireValue(method.definitionState.retiredAt === null, `${dimension} method is retired`);
  requireText(method.materialityContractCanonicalJson, `${dimension} materiality contract`);
  JSON.parse(method.materialityContractCanonicalJson);
  assertUnique(method.inputPolicies.map((policy) => policy.identity.id), `${dimension} policy id`);
  assertUnique(method.inputPolicies.map((policy) => policy.policyKey), `${dimension} policy key`);
  assertUnique(method.signalTypes.map((signal) => signal.identity.id), `${dimension} signal id`);
  assertUnique(
    method.signalTypes.map((signal) => signal.identity.code),
    `${dimension} signal code`,
  );
  assertUnique(
    method.mappingRelations.map((relation) => relation.relationRegistryId),
    `${dimension} relation id`,
  );
  requireValue(method.inputPolicies.length > 0, `${dimension} has no input policies`);
  requireValue(method.signalTypes.length > 0, `${dimension} has no signal types`);
  for (const policy of method.inputPolicies) {
    requireValue(policy.methodRegistryId === method.identity.id, "Policy/method identity drift");
    requireValue(policy.identity.version === "1", "Input-policy version drift");
    requireValue(policy.disposition === "ALLOWED" || policy.disposition === "FORBIDDEN", "Invalid policy disposition");
    assertUnique(
      policy.programFields.map((field) => `${field.recordType}\u0000${field.fieldName}`),
      "program field tuple",
    );
    for (const field of policy.programFields) {
      requireValue(field.methodRegistryId === method.identity.id, "Program field method drift");
      requireValue(field.inputPolicyRegistryId === policy.identity.id, "Program field policy drift");
    }
  }
  for (const signal of method.signalTypes) {
    requireValue(signal.methodRegistryId === method.identity.id, "Signal/method identity drift");
    requireValue(
      signal.allowedInferenceCategories.includes(method.inferenceCategory),
      "Method inference category is not allowed by its signal registry",
    );
  }
}

function validateManifestItem(
  item: DecisionManifestItem,
  dimension: FitDimension,
  input: FitEvaluationInput,
): void {
  const itemKeys: Readonly<Record<DecisionManifestItem["kind"], readonly string[]>> = {
    FIT_INTENT: ["kind", "ref", "intent"],
    STUDENT_ACCESS_CONTEXT: ["kind", "ref", "citizenshipCountryCode", "residenceCountryCode", "jurisdictionCode", "currentStatusCode", "authorizationPathCode", "targetPathCode"],
    PHASE2_GOAL: ["kind", "ref", "exposedFields", "goalType", "conceptId", "goalText"],
    PHASE2_PREFERENCE: ["kind", "ref", "exposedFields", "preferenceType", "value"],
    PHASE2_COURSE: ["kind", "ref", "exposedFields", "courseCode", "courseTitle", "courseStatus", "term"],
    PHASE2_COMPLETENESS: ["kind", "ref", "educationContextId", "domain", "completeness"],
    VERIFIED_MAPPING: ["kind", "ref", "mappingKind", "relationRegistryId", "relation", "conceptId", "statusAtPin", "reviewedAtAtPin", "verificationEvidenceIdAtPin", "retiredAtAtPin"],
    TAXONOMY_CONCEPT: ["kind", "ref", "conceptId", "activeInPinnedRelease"],
    CANONICAL_PROGRAM_FACT: ["kind", "ref", "recordId", "knowledgeStatus", "selectedObservationId", "fact"],
    HISTORICAL_CONTEXT_SELECTION: ["kind", "ref", "claimId", "selectionId", "observationId", "knowledgeStatus", "observationWorkflowStatusAtSelection", "observationReviewedAtAtSelection", "authority", "validFrom", "validTo", "programVersionId", "geographyCode", "jurisdictionCode", "pathCode", "value"],
    DIRECT_FINANCIAL_COMPARABLE: ["kind", "ref", "sourcePinId", "financialContractVersion", "financialConstraintIntentId", "comparable"],
    APPROVED_FINANCIAL_NORMALIZATION: ["kind", "ref", "normalizationId", "fieldObservationId", "financialConstraintIntentId", "intentSetId", "financialContractVersion", "methodCode", "methodVersion", "verificationEvidenceId", "source", "target", "conversionEvidenceId"],
  };
  assertExactKeys(item, itemKeys[item.kind], `${item.kind} manifest item`);
  assertExactKeys(
    item.ref,
    ["manifestItemKey", "sourceId", "methodRegistryId", "inputPolicyRegistryId", "methodCode", "policyKey", "sourceClass", "authorityRole"],
    "manifest ref",
  );
  const method = input.resolvedContract.methods[dimension];
  requireValue(item.ref.methodRegistryId === method.identity.id, "Manifest method identity drift");
  requireValue(item.ref.methodCode === METHOD_CONTRACT[dimension].code, "Manifest method code drift");
  const policy = method.inputPolicies.find(
    (candidate) => candidate.identity.id === item.ref.inputPolicyRegistryId,
  );
  requireValue(policy !== undefined, "Manifest references an unknown input policy");
  requireValue(policy.policyKey === item.ref.policyKey, "Manifest policy-key identity drift");
  requireValue(policy.disposition === "ALLOWED", "Manifest uses a forbidden input policy");
  const allowedDomains: readonly string[] =
    item.kind === "FIT_INTENT"
      ? ["FIT_INTENTS"]
      : item.kind === "STUDENT_ACCESS_CONTEXT"
        ? ["FIT_ACCESS_CONTEXT"]
        : item.kind === "PHASE2_GOAL"
          ? ["STUDENT_GOALS"]
          : item.kind === "PHASE2_PREFERENCE"
            ? ["STUDENT_PREFERENCES"]
            : item.kind === "PHASE2_COURSE"
              ? ["STUDENT_COURSES"]
              : item.kind === "PHASE2_COMPLETENESS"
                ? ["STUDENT_COMPLETENESS"]
                : item.kind === "VERIFIED_MAPPING"
                  ? ["CATALOG_MAPPINGS", "STUDENT_MAPPINGS", "FIT_CONTEXT_CLAIMS", "TAXONOMY_CONCEPTS"]
                  : item.kind === "TAXONOMY_CONCEPT"
                    ? ["TAXONOMY_CONCEPTS"]
                    : item.kind === "CANONICAL_PROGRAM_FACT"
                      ? ["PROGRAM_COURSES", "PROGRAM_COSTS", "PROGRAM_VERSIONS"]
                      : item.kind === "HISTORICAL_CONTEXT_SELECTION"
                        ? ["FIT_CONTEXT_CLAIMS"]
                        : item.kind === "DIRECT_FINANCIAL_COMPARABLE"
                          ? ["PROGRAM_COSTS"]
                          : ["FINANCIAL_NORMALIZATIONS"];
  requireValue(
    allowedDomains.includes(policy.inputDomain),
    `Manifest kind ${item.kind} is incompatible with policy domain ${policy.inputDomain}`,
  );
  const sourceClass = input.resolvedContract.semanticSourceClasses.find(
    (candidate) => candidate.sourceClassCode === item.ref.sourceClass,
  );
  requireValue(sourceClass !== undefined && sourceClass.fitPermitted, "Manifest uses a prohibited source class");
  const sourcePolicy = method.sourceClassPolicies.find(
    (candidate) => candidate.sourceClassCode === item.ref.sourceClass,
  );
  requireValue(sourcePolicy?.disposition === "ALLOWED", "Method does not allow the manifest source class");

  if (item.kind === "FIT_INTENT") {
    validateIntent(item.intent);
    requireValue(item.intent.dimension === dimension, "Intent crossed a dimension boundary");
  }
  if (item.kind === "VERIFIED_MAPPING") {
    requireValue(item.retiredAtAtPin === null, "Retired mapping entered the decision manifest");
    requireText(item.verificationEvidenceIdAtPin, "mapping verification evidence");
    requireIsoDate(item.reviewedAtAtPin, "mapping reviewedAt");
    const definition = input.resolvedContract.mappingRelationDefinitions.find(
      (candidate) => candidate.relationRegistryId === item.relationRegistryId,
    );
    requireValue(definition?.relationCode === item.relation, "Mapping relation definition drift");
    requireValue(
      method.mappingRelations.some(
        (candidate) =>
          candidate.relationRegistryId === item.relationRegistryId &&
          candidate.relationCode === item.relation,
      ),
      "Mapping relation is not permitted by the method",
    );
  }
  if (item.kind === "HISTORICAL_CONTEXT_SELECTION") {
    requireIsoDate(item.validFrom, "context validFrom");
    if (item.validTo !== null) requireIsoDate(item.validTo, "context validTo");
    if (item.knowledgeStatus === "KNOWN") {
      requireValue(item.value !== null, "KNOWN context selection requires a typed value");
      requireValue(
        item.observationWorkflowStatusAtSelection === "VERIFIED",
        "KNOWN context selection must be verified",
      );
    }
  }
  if (item.kind === "CANONICAL_PROGRAM_FACT") {
    requireValue(
      policy.programFields.some(
        (field) =>
          field.recordType === item.fact.recordType && field.fieldName === item.fact.field,
      ),
      "Canonical program fact is outside the exact policy field allowlist",
    );
  }
  if (item.kind === "DIRECT_FINANCIAL_COMPARABLE") {
    requireValue(dimension === "FINANCIAL", "Direct Financial comparable crossed dimensions");
    requireValue(
      item.financialContractVersion === "FINANCIAL_BILLING_BASIS_V014",
      "Unknown direct Financial contract version",
    );
    assertExactDecimal(item.comparable.amount, "direct comparable amount");
    assertUnique(item.comparable.components, "direct comparable component");
  }
  if (item.kind === "APPROVED_FINANCIAL_NORMALIZATION") {
    requireValue(dimension === "FINANCIAL", "Financial normalization crossed dimensions");
    requireValue(
      item.financialContractVersion === "FINANCIAL_BILLING_BASIS_V014",
      "Unknown Financial normalization contract",
    );
    const normalization = input.resolvedContract.financialNormalizations.find(
      (candidate) => candidate.identity.id === item.normalizationId,
    );
    requireValue(normalization !== undefined, "Normalization is absent from the resolved registry");
    requireValue(
      normalization.identity.code === item.methodCode &&
        normalization.identity.version === String(item.methodVersion),
      "Normalization method identity drift",
    );
    requireValue(
      normalization.definitionState.status === "VERIFIED" &&
        normalization.definitionState.retiredAt === null,
      "Normalization method is not active and verified",
    );
    requireValue(
      normalization.sourceScope === item.source.scope &&
        normalization.targetScope === item.target.scope &&
        normalization.sourcePeriod === item.source.period &&
        normalization.targetPeriod === item.target.period &&
        normalization.sourceBasis === item.source.basis &&
        normalization.targetBasis === item.target.basis &&
        (normalization.sourceCurrency === null ||
          normalization.sourceCurrency === item.source.currency) &&
        (normalization.targetCurrency === null ||
          normalization.targetCurrency === item.target.currency),
      "Normalization semantic contract drift",
    );
    assertExactDecimal(item.source.amount, "normalization source amount");
    assertExactDecimal(item.target.amount, "normalization target amount");
    assertUnique(item.source.components, "normalization source component");
    assertUnique(item.target.components, "normalization target component");
  }
}

export function validateFitInput(input: FitEvaluationInput): void {
  assertExactKeys(
    input,
    ["schemaVersion", "contractRelease", "resolvedContract", "evaluator", "evaluationAsOf", "profile", "intentSet", "programVersionId", "taxonomyReleaseCode", "methods", "manifest", "inputStates"],
    "FitEvaluationInput",
  );
  assertNoProhibitedDecisionKeys(input);
  requireValue(input.schemaVersion === "fit-v0.1", "Unsupported Fit schema version");
  requireIsoDate(input.evaluationAsOf, "evaluationAsOf");
  requireValue(input.contractRelease.releaseCode === "fit-v0.1", "Unsupported Fit release");
  requireValue(input.contractRelease.specificationVersion === "v0.1", "Unsupported Fit specification");
  requireValue(input.resolvedContract.release.code === "fit-v0.1", "Resolved release code drift");
  requireValue(input.resolvedContract.release.version === "v0.1", "Resolved release version drift");
  requireValue(
    input.contractRelease.registryId === input.resolvedContract.release.id &&
      input.contractRelease.digest === input.resolvedContract.release.specificationDigest,
    "Release identity or digest drift",
  );
  requireValue(input.resolvedContract.release.definitionState.status === "VERIFIED", "Release is not verified");
  requireValue(input.resolvedContract.release.definitionState.retiredAt === null, "Release is retired");
  requireValue(
    input.evaluator.registryId === input.resolvedContract.evaluatorBuild.id &&
      input.evaluator.name === input.resolvedContract.evaluatorBuild.evaluatorName &&
      input.evaluator.version === input.resolvedContract.evaluatorBuild.evaluatorVersion &&
      input.evaluator.buildHash === input.resolvedContract.evaluatorBuild.buildHash,
    "Evaluator-build identity drift",
  );
  requireValue(
    input.resolvedContract.evaluatorBuild.definitionState.status === "VERIFIED" &&
      input.resolvedContract.evaluatorBuild.definitionState.retiredAt === null,
    "Evaluator build is not active and verified",
  );
  requireText(input.profile.versionId, "profile version");
  requireText(input.profile.snapshotHash, "profile snapshot hash");
  requireText(input.intentSet.id, "intent set");
  requireText(input.intentSet.snapshotHash, "intent snapshot hash");
  requireText(input.programVersionId, "program version");
  requireText(input.taxonomyReleaseCode, "taxonomy release");

  const methodKeys = Object.keys(input.methods).sort();
  const contractMethodKeys = Object.keys(input.resolvedContract.methods).sort();
  const expectedKeys = [...FIT_DIMENSIONS].sort();
  requireValue(JSON.stringify(methodKeys) === JSON.stringify(expectedKeys), "Exactly six input methods are required");
  requireValue(
    JSON.stringify(contractMethodKeys) === JSON.stringify(expectedKeys),
    "Resolved contract must contain exactly six methods",
  );

  assertUnique(
    input.resolvedContract.semanticSourceClasses.map((value) => value.sourceClassRegistryId),
    "semantic source-class id",
  );
  assertUnique(
    input.resolvedContract.semanticSourceClasses.map((value) => value.sourceClassCode),
    "semantic source-class code",
  );
  assertUnique(
    input.resolvedContract.mappingRelationDefinitions.map((value) => value.relationRegistryId),
    "mapping relation id",
  );
  assertUnique(input.resolvedContract.reasons.map((reason) => reason.identity.id), "reason id");
  assertUnique(input.resolvedContract.reasons.map((reason) => reason.identity.code), "reason code");
  assertUnique(
    input.resolvedContract.financialNormalizations.map((value) => value.identity.id),
    "financial normalization id",
  );
  for (const reason of input.resolvedContract.reasons) {
    requireValue(
      reason.contractReleaseRegistryId === input.resolvedContract.release.id,
      "Reason belongs to another release",
    );
    requireValue(reason.definitionState.status === "VERIFIED" && reason.definitionState.retiredAt === null, "Reason is not active and verified");
  }

  const methodIdToDimension = new Map<string, FitDimension>();
  for (const dimension of FIT_DIMENSIONS) {
    const method = input.resolvedContract.methods[dimension];
    validateMethodContract(dimension, method);
    requireValue(!methodIdToDimension.has(method.identity.id), "Duplicate method registry identity");
    methodIdToDimension.set(method.identity.id, dimension);
    assertUnique(
      method.sourceClassPolicies.map((policy) => policy.sourceClassRegistryId),
      `${dimension} source-class policy`,
    );
    for (const sourcePolicy of method.sourceClassPolicies) {
      requireValue(sourcePolicy.methodRegistryId === method.identity.id, "Source-class policy method drift");
      const definition = input.resolvedContract.semanticSourceClasses.find(
        (candidate) => candidate.sourceClassRegistryId === sourcePolicy.sourceClassRegistryId,
      );
      requireValue(
        definition !== undefined && definition.sourceClassCode === sourcePolicy.sourceClassCode,
        "Source-class policy definition drift",
      );
    }
    for (const relation of method.mappingRelations) {
      requireValue(relation.methodRegistryId === method.identity.id, "Mapping-policy method drift");
      const definition = input.resolvedContract.mappingRelationDefinitions.find(
        (candidate) => candidate.relationRegistryId === relation.relationRegistryId,
      );
      requireValue(
        definition !== undefined && definition.relationCode === relation.relationCode,
        "Mapping-policy definition drift",
      );
      requireValue(
        !relation.permitsStrongAlignment || method.permitsStrongAlignment,
        "Mapping policy exceeds the method strong-alignment permission",
      );
    }
    for (const signal of method.signalTypes) {
      requireValue(
        !signal.permitsStrongAlignment || method.permitsStrongAlignment,
        "Signal exceeds the method strong-alignment permission",
      );
    }
    const supplied = input.methods[dimension];
    assertExactKeys(
      supplied,
      ["registryId", "methodCode", "methodVersion", "inferenceCategory", "permitsStrongAlignment"],
      `${dimension} method input`,
    );
    const expected = METHOD_CONTRACT[dimension];
    requireValue(
      supplied.registryId === method.identity.id &&
        supplied.methodCode === expected.code &&
        supplied.methodVersion === 1 &&
        supplied.inferenceCategory === expected.inferenceCategory &&
        supplied.permitsStrongAlignment === expected.permitsStrongAlignment,
      `Pinned method drift for ${dimension}`,
    );
  }

  for (const normalization of input.resolvedContract.financialNormalizations) {
    requireValue(
      normalization.contractReleaseRegistryId === input.resolvedContract.release.id,
      "Financial normalization belongs to another release",
    );
    requireValue(
      normalization.definitionState.status === "VERIFIED" &&
        normalization.definitionState.retiredAt === null,
      "Financial normalization is not active and verified",
    );
    requireText(
      normalization.normalizationContractCanonicalJson,
      "Financial normalization contract",
    );
    JSON.parse(normalization.normalizationContractCanonicalJson);
  }

  assertUnique(input.manifest.map((item) => item.ref.manifestItemKey), "manifest item key");
  assertUnique(
    input.manifest.map(
      (item) => `${item.ref.methodRegistryId}\u0000${item.kind}\u0000${item.ref.sourceId}`,
    ),
    "method/source manifest membership",
  );
  assertUnique(
    input.inputStates.map(
      (state) => `${state.methodRegistryId}\u0000${state.inputPolicyRegistryId}`,
    ),
    "input state",
  );
  const manifestByKey = new Map(input.manifest.map((item) => [item.ref.manifestItemKey, item]));
  const referenced = new Set<string>();
  for (const state of input.inputStates) {
    assertExactKeys(
      state,
      ["methodRegistryId", "inputPolicyRegistryId", "methodCode", "policyKey", "requirement", "availability", "manifestItemKeys", "completenessManifestItemKey", "provenanceManifestItemKey"],
      "Fit input state",
    );
    const dimension = methodIdToDimension.get(state.methodRegistryId);
    requireValue(dimension !== undefined, "Input state references an unknown method");
    const method = input.resolvedContract.methods[dimension];
    const policy = method.inputPolicies.find(
      (candidate) => candidate.identity.id === state.inputPolicyRegistryId,
    );
    requireValue(policy !== undefined, "Input state references an unknown policy");
    requireValue(
      state.methodCode === METHOD_CONTRACT[dimension].code &&
        state.policyKey === policy.policyKey &&
        state.requirement === policy.requirement,
      "Input-state registry projection drift",
    );
    assertUnique(state.manifestItemKeys, "input-state manifest key");
    if (state.availability === "INCLUDED") {
      requireValue(state.manifestItemKeys.length > 0, "INCLUDED state requires exact manifest membership");
    } else {
      requireValue(state.manifestItemKeys.length === 0, "Unavailable input cannot supply a value");
      requireValue(
        state.completenessManifestItemKey !== null || state.provenanceManifestItemKey !== null,
        "Unavailable input requires completeness or provenance",
      );
    }
    const stateRefs = [
      ...state.manifestItemKeys,
      state.completenessManifestItemKey,
      state.provenanceManifestItemKey,
    ].filter((value): value is string => value !== null);
    for (const key of stateRefs) {
      const item = manifestByKey.get(key);
      requireValue(item !== undefined, `Input state references missing manifest item ${key}`);
      requireValue(item.ref.methodRegistryId === state.methodRegistryId, "Input-state evidence crossed methods");
      referenced.add(key);
    }
  }
  requireValue(referenced.size === input.manifest.length, "Manifest contains unreferenced items");

  for (const item of input.manifest) {
    const dimension = methodIdToDimension.get(item.ref.methodRegistryId);
    requireValue(dimension !== undefined, "Manifest references an unknown method");
    validateManifestItem(item, dimension, input);
  }
}
