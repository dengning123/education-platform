import { FitAdapterError, FitSnapshotGateway, type FitDatabaseGateway } from "./database-gateway.js";
import type { FitEvaluationRequest } from "./request.js";

async function loadFitEvaluationSnapshotWith(
  database: FitDatabaseGateway,
  request: FitEvaluationRequest,
  snapshotFunction: "get_fit_evaluation_snapshot_v016" | "get_fit_product_evaluation_snapshot_v028",
  evaluationId?: string,
): Promise<FitSnapshotGateway> {
  let resumeSnapshot: Readonly<Record<string, readonly Record<string, unknown>[]>> = {};
  if (request.evidence.approvedFinancialNormalizationIds.length > 0) {
    if (evaluationId === undefined) throw new FitAdapterError("Approved normalization requires a resume evaluation", 400);
    const value = await database.rpc<unknown>("get_fit_financial_normalization_resume_snapshot_v017", {
      p_evaluation_id: evaluationId,
      p_financial_normalization_ids: request.evidence.approvedFinancialNormalizationIds,
    });
    if (value === null || typeof value !== "object" || Array.isArray(value)) {
      throw new FitAdapterError("Financial normalization resume snapshot is not a closed object", 500);
    }
    resumeSnapshot = value as Readonly<Record<string, readonly Record<string, unknown>[]>>;
  }
  const normalizationObservationIds = (resumeSnapshot.fit_financial_normalizations ?? [])
    .map((row) => row.field_observation_id)
    .filter((value): value is string => typeof value === "string");
  const basisObservationIds = (resumeSnapshot.fit_financial_source_pins_v014 ?? [])
    .map((row) => row.billing_basis_observation_id)
    .filter((value): value is string => typeof value === "string");
  const observationIds = [...new Set([
    ...request.evidence.canonicalObservationIds,
    ...request.evidence.directFinancialComparisons.flatMap((row) => [row.amountObservationId, row.billingBasisObservationId]),
    ...normalizationObservationIds,
    ...basisObservationIds,
  ])];
  const snapshot = await database.rpc<unknown>(snapshotFunction, {
    p_profile_version_id: request.profileVersionId,
    p_intent_set_id: request.intentSetId,
    p_program_version_id: request.programVersionId,
    p_taxonomy_release_code: request.taxonomyReleaseCode,
    p_observation_ids: observationIds,
    p_catalog_mapping_ids: request.evidence.catalogMappingIds,
    p_student_course_ids: request.evidence.studentCourseIds,
    p_student_mapping_ids: request.evidence.studentMappingIds,
    p_taxonomy_concept_ids: request.evidence.taxonomyConceptIds,
    p_context_claim_ids: request.evidence.contextClaimIds,
    p_context_mapping_ids: request.evidence.contextMappingIds,
  });
  if (snapshot === null || typeof snapshot !== "object" || Array.isArray(snapshot)) {
    throw new FitAdapterError("Fit source snapshot is not a closed object", 500);
  }
  const merged = { ...(snapshot as Record<string, readonly Record<string, unknown>[]>), ...resumeSnapshot };
  for (const [table, rows] of Object.entries(merged)) {
    if (!Array.isArray(rows) || rows.some((row) => row === null || typeof row !== "object" || Array.isArray(row))) {
      throw new FitAdapterError(`Fit source snapshot table ${table} is invalid`, 500);
    }
  }
  return new FitSnapshotGateway(merged);
}

export function loadFitEvaluationSnapshot(
  database: FitDatabaseGateway,
  request: FitEvaluationRequest,
  evaluationId?: string,
): Promise<FitSnapshotGateway> {
  return loadFitEvaluationSnapshotWith(database, request, "get_fit_evaluation_snapshot_v016", evaluationId);
}

export function loadProductFitEvaluationSnapshot(
  database: FitDatabaseGateway,
  request: FitEvaluationRequest,
): Promise<FitSnapshotGateway> {
  if (request.evidence.approvedFinancialNormalizationIds.length !== 0) {
    throw new FitAdapterError("Product Fit evaluation cannot start from a reviewed Financial normalization", 400);
  }
  return loadFitEvaluationSnapshotWith(database, request, "get_fit_product_evaluation_snapshot_v028");
}
