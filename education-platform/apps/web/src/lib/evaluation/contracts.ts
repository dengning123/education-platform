const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const HASH_PATTERN = /^[a-f0-9]{64}$/;
const MAX_LIST = 256;
const MAX_TEXT = 512;

export class EvaluationContractError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "EvaluationContractError";
  }
}

function object(value: unknown, label: string): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new EvaluationContractError(`${label} must be an object`);
  }
  return value as Record<string, unknown>;
}

function exactKeys(value: Record<string, unknown>, keys: readonly string[], label: string): void {
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  if (actual.length !== expected.length || actual.some((key, index) => key !== expected[index])) {
    throw new EvaluationContractError(`${label} must use the exact closed contract`);
  }
}

function text(value: unknown, label: string, max = MAX_TEXT): string {
  if (typeof value !== "string" || value.length === 0 || value.length > max) {
    throw new EvaluationContractError(`${label} must be bounded text`);
  }
  return value;
}

function uuid(value: unknown, label: string): string {
  const result = text(value, label, 36);
  if (!UUID_PATTERN.test(result)) throw new EvaluationContractError(`${label} must be a UUID`);
  return result;
}

function nullableUuid(value: unknown, label: string): string | null {
  return value === null ? null : uuid(value, label);
}

function hash(value: unknown, label: string): string {
  const result = text(value, label, 64);
  if (!HASH_PATTERN.test(result)) throw new EvaluationContractError(`${label} must be a SHA-256 identity`);
  return result;
}

function stringArray(value: unknown, label: string, validator: (item: unknown, itemLabel: string) => string = text): string[] {
  if (!Array.isArray(value) || value.length > MAX_LIST) throw new EvaluationContractError(`${label} must be a bounded array`);
  const result = value.map((item, index) => validator(item, `${label}[${index}]`));
  if (new Set(result).size !== result.length) throw new EvaluationContractError(`${label} must not contain duplicates`);
  return result;
}

export type EligibilityConnectionRequest = Readonly<{
  profileVersionId: string;
  programVersionId: string;
  operationId: string;
}>;

export function parseEligibilityConnectionRequest(value: unknown): EligibilityConnectionRequest {
  const request = object(value, "request");
  exactKeys(request, ["profileVersionId", "programVersionId", "operationId"], "request");
  return {
    profileVersionId: uuid(request.profileVersionId, "profileVersionId"),
    programVersionId: uuid(request.programVersionId, "programVersionId"),
    operationId: uuid(request.operationId, "operationId"),
  };
}

export type FitConnectionRequest = Readonly<{
  profileVersionId: string;
  intentSetId: string;
  programVersionId: string;
  taxonomyReleaseCode: string;
  supersedesEvaluationId: string | null;
  eligibilityContextEvaluationId: string | null;
  evidence: Readonly<{
    canonicalObservationIds: readonly string[];
    catalogMappingIds: readonly string[];
    studentCourseIds: readonly string[];
    studentMappingIds: readonly string[];
    taxonomyConceptIds: readonly string[];
    contextClaimIds: readonly string[];
    contextMappingIds: readonly string[];
    accessContextId: string | null;
    directFinancialComparisons: readonly Readonly<{
      financialIntentId: string;
      amountObservationId: string;
      billingBasisObservationId: string;
    }>[];
    approvedFinancialNormalizationIds: readonly string[];
  }>;
}>;

export function parseFitConnectionRequest(value: unknown): FitConnectionRequest {
  const request = object(value, "request");
  exactKeys(request, [
    "profileVersionId", "intentSetId", "programVersionId", "taxonomyReleaseCode",
    "supersedesEvaluationId", "eligibilityContextEvaluationId", "evidence",
  ], "request");
  const evidence = object(request.evidence, "evidence");
  exactKeys(evidence, [
    "canonicalObservationIds", "catalogMappingIds", "studentCourseIds", "studentMappingIds",
    "taxonomyConceptIds", "contextClaimIds", "contextMappingIds", "accessContextId",
    "directFinancialComparisons", "approvedFinancialNormalizationIds",
  ], "evidence");
  if (!Array.isArray(evidence.directFinancialComparisons) || evidence.directFinancialComparisons.length > MAX_LIST) {
    throw new EvaluationContractError("directFinancialComparisons must be a bounded array");
  }
  const directFinancialComparisons = evidence.directFinancialComparisons.map((item, index) => {
    const row = object(item, `directFinancialComparisons[${index}]`);
    exactKeys(row, ["financialIntentId", "amountObservationId", "billingBasisObservationId"], `directFinancialComparisons[${index}]`);
    return {
      financialIntentId: uuid(row.financialIntentId, "financialIntentId"),
      amountObservationId: uuid(row.amountObservationId, "amountObservationId"),
      billingBasisObservationId: uuid(row.billingBasisObservationId, "billingBasisObservationId"),
    };
  });
  if (new Set(directFinancialComparisons.map((row) => row.financialIntentId)).size !== directFinancialComparisons.length) {
    throw new EvaluationContractError("Only one direct Financial comparison is allowed per intent");
  }
  const taxonomyReleaseCode = text(request.taxonomyReleaseCode, "taxonomyReleaseCode", 64);
  if (!/^[A-Za-z0-9._-]+$/.test(taxonomyReleaseCode)) throw new EvaluationContractError("taxonomyReleaseCode is invalid");
  return {
    profileVersionId: uuid(request.profileVersionId, "profileVersionId"),
    intentSetId: uuid(request.intentSetId, "intentSetId"),
    programVersionId: uuid(request.programVersionId, "programVersionId"),
    taxonomyReleaseCode,
    supersedesEvaluationId: nullableUuid(request.supersedesEvaluationId, "supersedesEvaluationId"),
    eligibilityContextEvaluationId: nullableUuid(request.eligibilityContextEvaluationId, "eligibilityContextEvaluationId"),
    evidence: {
      canonicalObservationIds: stringArray(evidence.canonicalObservationIds, "canonicalObservationIds", uuid),
      catalogMappingIds: stringArray(evidence.catalogMappingIds, "catalogMappingIds", uuid),
      studentCourseIds: stringArray(evidence.studentCourseIds, "studentCourseIds", uuid),
      studentMappingIds: stringArray(evidence.studentMappingIds, "studentMappingIds", uuid),
      taxonomyConceptIds: stringArray(evidence.taxonomyConceptIds, "taxonomyConceptIds", uuid),
      contextClaimIds: stringArray(evidence.contextClaimIds, "contextClaimIds", uuid),
      contextMappingIds: stringArray(evidence.contextMappingIds, "contextMappingIds", uuid),
      accessContextId: nullableUuid(evidence.accessContextId, "accessContextId"),
      directFinancialComparisons,
      approvedFinancialNormalizationIds: stringArray(evidence.approvedFinancialNormalizationIds, "approvedFinancialNormalizationIds", uuid),
    },
  };
}

export type EligibilityRequirementSummary = Readonly<{
  id: string;
  truth: "SATISFIED" | "NOT_SATISFIED" | "UNKNOWN";
  reasonCodes: readonly string[];
  explanation: string;
  missingDataCodes: readonly string[];
  supportingReferenceCount: number;
}>;

export type EligibilityConnectionResult = Readonly<{
  schemaVersion: "ELIGIBILITY_PRODUCTION_ASSEMBLY_V026";
  evalId: string;
  profileId: string;
  programId: string;
  status: "ELIGIBLE" | "NOT_ELIGIBLE" | "UNKNOWN" | "CONDITIONALLY_ELIGIBLE";
  rootTruth: "SATISFIED" | "NOT_SATISFIED" | "UNKNOWN";
  requirements: readonly EligibilityRequirementSummary[];
  inputFingerprint: string;
  resultFingerprint: string;
}>;

const truthValues = new Set(["SATISFIED", "NOT_SATISFIED", "UNKNOWN"]);
const outcomes = new Set(["ELIGIBLE", "NOT_ELIGIBLE", "UNKNOWN", "CONDITIONALLY_ELIGIBLE"]);

export function projectEligibilityAssemblyResult(value: unknown): EligibilityConnectionResult {
  const response = object(value, "Eligibility assembly response");
  exactKeys(response, [
    "schemaVersion", "evalId", "profileId", "programId", "status", "rootTruth",
    "requirements", "inputFingerprint", "resultFingerprint",
  ], "Eligibility assembly response");
  if (response.schemaVersion !== "ELIGIBILITY_PRODUCTION_ASSEMBLY_V026") {
    throw new EvaluationContractError("Unsupported Eligibility assembly schema version");
  }
  const status = text(response.status, "status", 32);
  const rootTruth = text(response.rootTruth, "rootTruth", 32);
  if (!outcomes.has(status) || !truthValues.has(rootTruth)) {
    throw new EvaluationContractError("Eligibility assembly result is invalid");
  }
  if (!Array.isArray(response.requirements) || response.requirements.length > MAX_LIST) {
    throw new EvaluationContractError("Eligibility requirements are not bounded");
  }
  const requirements = response.requirements.map((value, index) => {
    const row = object(value, `requirements[${index}]`);
    exactKeys(row, [
      "id", "truth", "reasonCodes", "explanation", "missingDataCodes",
      "supportingReferenceCount",
    ], `requirements[${index}]`);
    const truth = text(row.truth, "truth", 32);
    if (!truthValues.has(truth)) throw new EvaluationContractError("Unknown Eligibility truth value");
    const supportingReferenceCount = row.supportingReferenceCount;
    if (!Number.isSafeInteger(supportingReferenceCount) || (supportingReferenceCount as number) < 0 || (supportingReferenceCount as number) > MAX_LIST) {
      throw new EvaluationContractError("supportingReferenceCount must be bounded");
    }
    return {
      id: uuid(row.id, "id"),
      truth: truth as EligibilityRequirementSummary["truth"],
      reasonCodes: stringArray(row.reasonCodes, "reasonCodes", (item, label) => text(item, label, 96)),
      explanation: text(row.explanation, "explanation", 2_000),
      missingDataCodes: stringArray(row.missingDataCodes, "missingDataCodes", (item, label) => text(item, label, 96)),
      supportingReferenceCount: supportingReferenceCount as number,
    };
  });
  return {
    schemaVersion: "ELIGIBILITY_PRODUCTION_ASSEMBLY_V026",
    evalId: uuid(response.evalId, "evalId"),
    profileId: uuid(response.profileId, "profileId"),
    programId: uuid(response.programId, "programId"),
    status: status as EligibilityConnectionResult["status"],
    rootTruth: rootTruth as EligibilityConnectionResult["rootTruth"],
    requirements,
    inputFingerprint: hash(response.inputFingerprint, "inputFingerprint"),
    resultFingerprint: hash(response.resultFingerprint, "resultFingerprint"),
  };
}

export const FIT_DIMENSIONS = [
  "ACADEMIC", "CAREER", "FINANCIAL", "GEOGRAPHIC_DELIVERY", "PERSONAL_PREFERENCE", "INTERNATIONAL_ACCESSIBILITY",
] as const;
type FitDimension = (typeof FIT_DIMENSIONS)[number];

export type FitConnectionResult = Readonly<{
  schemaVersion: "FIT_CONNECTION_RESULT_V1";
  engineSchemaVersion: "fit-v0.1";
  fitEvaluationId: string;
  candidateInputFingerprint: string;
  resultFingerprint: string;
  dimensions: Readonly<Record<FitDimension, Readonly<{
    assessment: string;
    confidence: string;
    evidenceCoverage: string;
    inferenceCategory: string;
    reasonCodes: readonly string[];
    limitingInputCodes: readonly string[];
  }>>>;
}>;

const dimensionKeys = [
  "dimension", "methodRegistryId", "methodCode", "methodVersion", "assessment", "confidence",
  "evidenceCoverage", "inferenceCategory", "signals", "reasons", "limitingInputs", "exactManifestRefs",
] as const;
const reasonKeys = [
  "methodRegistryId", "reasonDefinitionRegistryId", "reasonCode", "direction", "signalCode",
  "signalTypeRegistryId", "inputPolicyKey", "inputPolicyRegistryId", "mappingRelationRegistryId", "exactManifestRefs",
] as const;
const limitingKeys = [
  "methodRegistryId", "reasonCode", "reasonDefinitionRegistryId", "inputPolicyKey", "inputPolicyRegistryId",
  "availability", "completenessManifestRef", "provenanceManifestRef",
] as const;
const signalKeys = [
  "methodRegistryId", "signalTypeRegistryId", "inputPolicyRegistryIds", "mappingRelationRegistryId", "signalCode",
  "direction", "material", "inferenceCategory", "evidenceManifestRefs", "intentManifestRef",
  "requiredConstraintContradiction", "internationalHighImpact", "model",
] as const;

export function projectFitEdgeResult(value: unknown): FitConnectionResult {
  const response = object(value, "Fit response");
  exactKeys(response, ["evaluationId", "candidateInputFingerprint", "resultFingerprint", "schemaVersion", "dimensions"], "Fit response");
  if (response.schemaVersion !== "fit-v0.1") throw new EvaluationContractError("Unsupported Fit schema version");
  const rawDimensions = object(response.dimensions, "Fit dimensions");
  exactKeys(rawDimensions, FIT_DIMENSIONS, "Fit dimensions");
  const dimensions = {} as Record<FitDimension, {
    assessment: string; confidence: string; evidenceCoverage: string; inferenceCategory: string;
    reasonCodes: string[]; limitingInputCodes: string[];
  }>;
  for (const dimension of FIT_DIMENSIONS) {
    const row = object(rawDimensions[dimension], `Fit dimension ${dimension}`);
    exactKeys(row, dimensionKeys, `Fit dimension ${dimension}`);
    if (row.dimension !== dimension || row.methodVersion !== 1) throw new EvaluationContractError("Fit dimension identity is invalid");
    if (!Array.isArray(row.signals) || !Array.isArray(row.reasons) || !Array.isArray(row.limitingInputs) || !Array.isArray(row.exactManifestRefs)) {
      throw new EvaluationContractError("Fit dimension arrays are invalid");
    }
    if (row.signals.length > MAX_LIST || row.reasons.length > MAX_LIST || row.limitingInputs.length > MAX_LIST || row.exactManifestRefs.length > MAX_LIST) {
      throw new EvaluationContractError("Fit dimension arrays are too large");
    }
    for (const [index, signalValue] of row.signals.entries()) exactKeys(object(signalValue, `signal[${index}]`), signalKeys, `signal[${index}]`);
    const reasonCodes = row.reasons.map((reasonValue, index) => {
      const reason = object(reasonValue, `reason[${index}]`);
      exactKeys(reason, reasonKeys, `reason[${index}]`);
      return text(reason.reasonCode, "reasonCode", 96);
    });
    const limitingInputCodes = row.limitingInputs.map((limitingValue, index) => {
      const limiting = object(limitingValue, `limitingInput[${index}]`);
      exactKeys(limiting, limitingKeys, `limitingInput[${index}]`);
      return text(limiting.reasonCode, "limitingInput.reasonCode", 96);
    });
    dimensions[dimension] = {
      assessment: text(row.assessment, "assessment", 64),
      confidence: text(row.confidence, "confidence", 32),
      evidenceCoverage: text(row.evidenceCoverage, "evidenceCoverage", 32),
      inferenceCategory: text(row.inferenceCategory, "inferenceCategory", 32),
      reasonCodes,
      limitingInputCodes,
    };
  }
  return {
    schemaVersion: "FIT_CONNECTION_RESULT_V1",
    engineSchemaVersion: "fit-v0.1",
    fitEvaluationId: uuid(response.evaluationId, "evaluationId"),
    candidateInputFingerprint: hash(response.candidateInputFingerprint, "candidateInputFingerprint"),
    resultFingerprint: hash(response.resultFingerprint, "resultFingerprint"),
    dimensions,
  };
}
