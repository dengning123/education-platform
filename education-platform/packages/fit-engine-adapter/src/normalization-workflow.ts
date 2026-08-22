import {
  canonicalFitOutputJson,
  canonicalizeFitEvaluationInput,
  evaluateFit,
} from "@education-platform/fit-engine";
import { FitAdapterError, type FitDatabaseGateway, requireOne } from "./database-gateway.js";
import { PRODUCTION_EVALUATOR_NAME, PRODUCTION_EVALUATOR_VERSION, type ExecutedFitEvaluation } from "./execute.js";
import { resolveFitEvaluationInput } from "./input-resolver.js";
import { persistFitEvaluation, type ApprovedFinancialNormalizationAssembly } from "./persistence.js";
import { resolveFitContract } from "./registry-resolver.js";
import type { FitEvaluationResumeRequest, FitFinancialNormalizationDraftRequest } from "./request.js";
import { loadFitEvaluationSnapshot } from "./snapshot.js";

type EvaluationRow = {
  evaluation_id: string;
  profile_version_id: string;
  intent_set_id: string;
  program_version_id: string;
  taxonomy_release_code: string;
  contract_release_id: string;
  evaluator_build_id: string;
  evaluation_as_of: string;
  evaluation_state: string;
  candidate_input_fingerprint: string | null;
};

type PreparedNormalization = {
  evaluationId: string;
  normalizationId: string;
  reviewState: "DRAFT";
};

type SourcePinRow = {
  source_pin_id: string;
  evaluation_id: string;
  amount_manifest_item_id: string;
  basis_manifest_item_id: string;
  amount_observation_id: string;
  billing_basis_observation_id: string;
};

type NormalizationRow = {
  financial_normalization_id: string;
  evaluation_id: string;
  source_pin_id: string;
};
type ConversionInputRow = {
  financial_normalization_id: string;
  input_role: string;
  intent_declaration_id: string | null;
};

export async function prepareFitFinancialNormalization(
  database: FitDatabaseGateway,
  request: FitFinancialNormalizationDraftRequest,
): Promise<PreparedNormalization> {
  const sourceDatabase = await loadFitEvaluationSnapshot(database, request.evaluation);
  const contract = await resolveFitContract(sourceDatabase, {
    evaluatorName: PRODUCTION_EVALUATOR_NAME,
    evaluatorVersion: PRODUCTION_EVALUATOR_VERSION,
  });
  const evaluationId = await database.rpc<string>("start_fit_evaluation", {
    p_profile_version_id: request.evaluation.profileVersionId,
    p_intent_set_id: request.evaluation.intentSetId,
    p_program_version_id: request.evaluation.programVersionId,
    p_taxonomy_release_code: request.evaluation.taxonomyReleaseCode,
    p_contract_release_id: contract.release.id,
    p_evaluator_build_id: contract.evaluatorBuild.id,
    p_supersedes_evaluation_id: request.evaluation.supersedesEvaluationId,
    p_eligibility_context_evaluation_id: request.evaluation.eligibilityContextEvaluationId,
  });
  await database.rpc("authorize_fit_evaluation_assembly", {
    p_evaluation_id: evaluationId,
    p_evaluator_build_hash: contract.evaluatorBuild.buildHash,
  });
  try {
    const prepared = await database.rpc<{
      evaluationId: string;
      normalizationId: string;
      reviewState: "DRAFT";
    }>("prepare_fit_financial_normalization_v017", {
      p_evaluation_id: evaluationId,
      p_amount_observation_id: request.draft.amountObservationId,
      p_billing_basis_observation_id: request.draft.billingBasisObservationId,
      p_financial_constraint_id: request.draft.financialIntentId,
      p_normalization_method_code: request.draft.normalizationMethodCode,
      p_normalization_method_version: request.draft.normalizationMethodVersion,
      p_conversion_evidence_id: request.draft.conversionEvidenceId,
      p_academic_years: request.draft.academicYears,
      p_rounding: request.draft.rounding,
      p_funding_intent_id: request.draft.fundingIntentId,
    });
    if (prepared.evaluationId !== evaluationId || prepared.reviewState !== "DRAFT") {
      throw new FitAdapterError("Prepared Financial normalization response drift", 500);
    }
    return prepared;
  } catch (error) {
    if (error instanceof FitAdapterError) throw new FitAdapterError(error.message, error.status, { evaluationId, detail: error.detail });
    throw error;
  }
}

export async function resumeFitEvaluation(
  database: FitDatabaseGateway,
  request: FitEvaluationResumeRequest,
): Promise<ExecutedFitEvaluation> {
  const sourceDatabase = await loadFitEvaluationSnapshot(database, request.evaluation, request.evaluationId);
  const contract = await resolveFitContract(sourceDatabase, {
    evaluatorName: PRODUCTION_EVALUATOR_NAME,
    evaluatorVersion: PRODUCTION_EVALUATOR_VERSION,
  });
  const evaluation = requireOne(await sourceDatabase.select<EvaluationRow>("fit_evaluations", {
    select: "*",
    evaluation_id: `eq.${request.evaluationId}`,
  }), "resumable Fit evaluation");
  if (
    evaluation.evaluation_state !== "BUILDING" || evaluation.candidate_input_fingerprint !== null ||
    evaluation.profile_version_id !== request.evaluation.profileVersionId ||
    evaluation.intent_set_id !== request.evaluation.intentSetId ||
    evaluation.program_version_id !== request.evaluation.programVersionId ||
    evaluation.taxonomy_release_code !== request.evaluation.taxonomyReleaseCode ||
    evaluation.contract_release_id !== contract.release.id ||
    evaluation.evaluator_build_id !== contract.evaluatorBuild.id
  ) {
    throw new FitAdapterError("Resume request does not exactly match an unsealed BUILDING evaluation", 409);
  }
  const normalization = requireOne(await sourceDatabase.select<NormalizationRow>("fit_financial_normalizations", {
    select: "financial_normalization_id,evaluation_id,source_pin_id",
    financial_normalization_id: `eq.${request.normalizationId}`,
  }), "reviewed Financial normalization");
  const sourcePin = requireOne((await sourceDatabase.select<SourcePinRow>("fit_financial_source_pins_v014", { select: "*" }))
    .filter((candidate) => candidate.source_pin_id === normalization.source_pin_id && candidate.evaluation_id === request.evaluationId), "Financial source pin");
  const fundingInputs = (await sourceDatabase.select<ConversionInputRow>("fit_financial_conversion_inputs_v014", { select: "*" }))
    .filter((candidate) => candidate.financial_normalization_id === normalization.financial_normalization_id && candidate.input_role === "AVAILABLE_FUNDING");
  if (fundingInputs.length > 1 || (fundingInputs.length === 1 && fundingInputs[0]!.intent_declaration_id === null)) {
    throw new FitAdapterError("Reviewed Financial funding provenance is invalid", 422);
  }
  const assembly: ApprovedFinancialNormalizationAssembly = {
    normalizationId: normalization.financial_normalization_id,
    amountManifestItemId: sourcePin.amount_manifest_item_id,
    basisManifestItemId: sourcePin.basis_manifest_item_id,
    amountObservationId: sourcePin.amount_observation_id,
    basisObservationId: sourcePin.billing_basis_observation_id,
    fundingIntentId: fundingInputs[0]?.intent_declaration_id ?? null,
  };
  const input = canonicalizeFitEvaluationInput(await resolveFitEvaluationInput(
    sourceDatabase,
    contract,
    request.evaluation,
    evaluation.evaluation_as_of,
  ));
  const output = evaluateFit(input);
  canonicalFitOutputJson(output);
  const fingerprints = await persistFitEvaluation(database, request.evaluationId, input, output, [assembly]);
  return { evaluationId: request.evaluationId, ...fingerprints, output };
}
