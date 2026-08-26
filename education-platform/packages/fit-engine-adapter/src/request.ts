import { FitAdapterError } from "./database-gateway.js";

export type DirectFinancialSelection = Readonly<{
  financialIntentId: string;
  amountObservationId: string;
  billingBasisObservationId: string;
}>;

export type FitEvaluationRequest = Readonly<{
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
    directFinancialComparisons: readonly DirectFinancialSelection[];
    approvedFinancialNormalizationIds: readonly string[];
  }>;
}>;

export type ProductFitEvaluationRequest = Readonly<{
  schemaVersion: "FIT_PRODUCT_EVALUATION_REQUEST_V027";
  profileVersionId: string;
  intentSetId: string;
  programVersionId: string;
  eligibilityContextEvaluationId: string | null;
}>;

export type FitFinancialNormalizationDraftRequest = Readonly<{
  evaluation: FitEvaluationRequest;
  draft: Readonly<{
    financialIntentId: string;
    amountObservationId: string;
    billingBasisObservationId: string;
    normalizationMethodCode: "ANNUAL_TO_PROGRAM" | "ANNUAL_TO_NET_PROGRAM";
    normalizationMethodVersion: 1;
    conversionEvidenceId: string;
    academicYears: string;
    rounding: "NONE";
    fundingIntentId: string | null;
  }>;
}>;

export type FitFinancialNormalizationReviewRequest = Readonly<{
  normalizationId: string;
  verificationEvidenceId: string;
}>;

export type FitEvaluationResumeRequest = Readonly<{
  evaluationId: string;
  normalizationId: string;
  evaluation: FitEvaluationRequest;
}>;

function object(value: unknown, label: string): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new FitAdapterError(`${label} must be an object`, 400);
  }
  return value as Record<string, unknown>;
}

function exactKeys(value: Record<string, unknown>, keys: readonly string[], label: string): void {
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  if (actual.length !== expected.length || actual.some((key, index) => key !== expected[index])) {
    throw new FitAdapterError(`${label} must use the exact closed request contract`, 400);
  }
}

function text(value: unknown, label: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new FitAdapterError(`${label} is required`, 400);
  }
  return value;
}

function nullableText(value: unknown, label: string): string | null {
  return value === null ? null : text(value, label);
}

function textArray(value: unknown, label: string): string[] {
  if (!Array.isArray(value)) throw new FitAdapterError(`${label} must be an array`, 400);
  const values = value.map((item, index) => text(item, `${label}[${index}]`));
  if (new Set(values).size !== values.length) throw new FitAdapterError(`${label} contains duplicates`, 400);
  return values;
}

function exactDecimal(value: unknown, label: string): string {
  const result = text(value, label);
  if (!/^(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$/.test(result) || Number(result) <= 0) {
    throw new FitAdapterError(`${label} must be a positive exact decimal string`, 400);
  }
  return result;
}

export function isProductFitEvaluationRequest(value: unknown): boolean {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    && (value as Record<string, unknown>).schemaVersion === "FIT_PRODUCT_EVALUATION_REQUEST_V027";
}

export function parseProductFitEvaluationRequest(value: unknown): ProductFitEvaluationRequest {
  const request = object(value, "request");
  exactKeys(request, ["schemaVersion", "profileVersionId", "intentSetId", "programVersionId", "eligibilityContextEvaluationId"], "request");
  if (request.schemaVersion !== "FIT_PRODUCT_EVALUATION_REQUEST_V027") {
    throw new FitAdapterError("Unsupported product Fit request schema", 400);
  }
  return {
    schemaVersion: "FIT_PRODUCT_EVALUATION_REQUEST_V027",
    profileVersionId: text(request.profileVersionId, "profileVersionId"),
    intentSetId: text(request.intentSetId, "intentSetId"),
    programVersionId: text(request.programVersionId, "programVersionId"),
    eligibilityContextEvaluationId: nullableText(request.eligibilityContextEvaluationId, "eligibilityContextEvaluationId"),
  };
}

export function parseFitEvaluationRequest(value: unknown): FitEvaluationRequest {
  const request = object(value, "request");
  exactKeys(request, [
    "profileVersionId",
    "intentSetId",
    "programVersionId",
    "taxonomyReleaseCode",
    "supersedesEvaluationId",
    "eligibilityContextEvaluationId",
    "evidence",
  ], "request");
  const evidence = object(request.evidence, "request.evidence");
  exactKeys(evidence, [
    "canonicalObservationIds",
    "catalogMappingIds",
    "studentCourseIds",
    "studentMappingIds",
    "taxonomyConceptIds",
    "contextClaimIds",
    "contextMappingIds",
    "accessContextId",
    "directFinancialComparisons",
    "approvedFinancialNormalizationIds",
  ], "request.evidence");
  if (!Array.isArray(evidence.directFinancialComparisons)) {
    throw new FitAdapterError("directFinancialComparisons must be an array", 400);
  }
  const directFinancialComparisons = evidence.directFinancialComparisons.map((item, index) => {
    const row = object(item, `directFinancialComparisons[${index}]`);
    exactKeys(row, ["financialIntentId", "amountObservationId", "billingBasisObservationId"], `directFinancialComparisons[${index}]`);
    return {
      financialIntentId: text(row.financialIntentId, "financialIntentId"),
      amountObservationId: text(row.amountObservationId, "amountObservationId"),
      billingBasisObservationId: text(row.billingBasisObservationId, "billingBasisObservationId"),
    };
  });
  const directKeys = directFinancialComparisons.map((item) => item.financialIntentId);
  if (new Set(directKeys).size !== directKeys.length) {
    throw new FitAdapterError("Only one direct Financial comparison is allowed per intent", 400);
  }
  return {
    profileVersionId: text(request.profileVersionId, "profileVersionId"),
    intentSetId: text(request.intentSetId, "intentSetId"),
    programVersionId: text(request.programVersionId, "programVersionId"),
    taxonomyReleaseCode: text(request.taxonomyReleaseCode, "taxonomyReleaseCode"),
    supersedesEvaluationId: nullableText(request.supersedesEvaluationId, "supersedesEvaluationId"),
    eligibilityContextEvaluationId: nullableText(request.eligibilityContextEvaluationId, "eligibilityContextEvaluationId"),
    evidence: {
      canonicalObservationIds: textArray(evidence.canonicalObservationIds, "canonicalObservationIds"),
      catalogMappingIds: textArray(evidence.catalogMappingIds, "catalogMappingIds"),
      studentCourseIds: textArray(evidence.studentCourseIds, "studentCourseIds"),
      studentMappingIds: textArray(evidence.studentMappingIds, "studentMappingIds"),
      taxonomyConceptIds: textArray(evidence.taxonomyConceptIds, "taxonomyConceptIds"),
      contextClaimIds: textArray(evidence.contextClaimIds, "contextClaimIds"),
      contextMappingIds: textArray(evidence.contextMappingIds, "contextMappingIds"),
      accessContextId: nullableText(evidence.accessContextId, "accessContextId"),
      directFinancialComparisons,
      approvedFinancialNormalizationIds: textArray(evidence.approvedFinancialNormalizationIds, "approvedFinancialNormalizationIds"),
    },
  };
}

export function parseFitFinancialNormalizationDraftRequest(value: unknown): FitFinancialNormalizationDraftRequest {
  const request = object(value, "request");
  exactKeys(request, ["evaluation", "draft"], "request");
  const evaluation = parseFitEvaluationRequest(request.evaluation);
  if (evaluation.evidence.directFinancialComparisons.length !== 0 || evaluation.evidence.approvedFinancialNormalizationIds.length !== 0) {
    throw new FitAdapterError("Normalization preparation cannot include completed Financial comparisons", 400);
  }
  const draft = object(request.draft, "request.draft");
  exactKeys(draft, [
    "financialIntentId",
    "amountObservationId",
    "billingBasisObservationId",
    "normalizationMethodCode",
    "normalizationMethodVersion",
    "conversionEvidenceId",
    "academicYears",
    "rounding",
    "fundingIntentId",
  ], "request.draft");
  if (draft.normalizationMethodCode !== "ANNUAL_TO_PROGRAM" && draft.normalizationMethodCode !== "ANNUAL_TO_NET_PROGRAM") {
    throw new FitAdapterError("Unsupported normalization method", 400);
  }
  if (draft.normalizationMethodVersion !== 1) throw new FitAdapterError("Unsupported normalization method version", 400);
  if (draft.rounding !== "NONE") {
    throw new FitAdapterError("The v017 normalization methods permit only exact no-rounding arithmetic", 400);
  }
  const fundingIntentId = nullableText(draft.fundingIntentId, "fundingIntentId");
  if ((draft.normalizationMethodCode === "ANNUAL_TO_NET_PROGRAM") !== (fundingIntentId !== null)) {
    throw new FitAdapterError("Net normalization requires exactly one funding intent; gross normalization forbids it", 400);
  }
  return {
    evaluation,
    draft: {
      financialIntentId: text(draft.financialIntentId, "financialIntentId"),
      amountObservationId: text(draft.amountObservationId, "amountObservationId"),
      billingBasisObservationId: text(draft.billingBasisObservationId, "billingBasisObservationId"),
      normalizationMethodCode: draft.normalizationMethodCode,
      normalizationMethodVersion: 1,
      conversionEvidenceId: text(draft.conversionEvidenceId, "conversionEvidenceId"),
      academicYears: exactDecimal(draft.academicYears, "academicYears"),
      rounding: "NONE",
      fundingIntentId,
    },
  };
}

export function parseFitFinancialNormalizationReviewRequest(value: unknown): FitFinancialNormalizationReviewRequest {
  const request = object(value, "request");
  exactKeys(request, ["normalizationId", "verificationEvidenceId"], "request");
  return {
    normalizationId: text(request.normalizationId, "normalizationId"),
    verificationEvidenceId: text(request.verificationEvidenceId, "verificationEvidenceId"),
  };
}

export function parseFitEvaluationResumeRequest(value: unknown): FitEvaluationResumeRequest {
  const request = object(value, "request");
  exactKeys(request, ["evaluationId", "normalizationId", "evaluation"], "request");
  const evaluationId = text(request.evaluationId, "evaluationId");
  const normalizationId = text(request.normalizationId, "normalizationId");
  const evaluation = parseFitEvaluationRequest(request.evaluation);
  if (evaluation.evidence.directFinancialComparisons.length !== 0 ||
      evaluation.evidence.approvedFinancialNormalizationIds.length !== 1 ||
      evaluation.evidence.approvedFinancialNormalizationIds[0] !== normalizationId) {
    throw new FitAdapterError("Resume requires exactly the reviewed normalization and no direct Financial comparison", 400);
  }
  return { evaluationId, normalizationId, evaluation };
}
