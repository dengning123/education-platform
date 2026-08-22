import {
  canonicalFitOutputJson,
  canonicalizeFitEvaluationInput,
  evaluateFit,
  type FitEvaluationOutput,
} from "@education-platform/fit-engine";
import { FitAdapterError, type FitDatabaseGateway, requireOne } from "./database-gateway.js";
import { resolveFitEvaluationInput } from "./input-resolver.js";
import { persistFitEvaluation } from "./persistence.js";
import { resolveFitContract } from "./registry-resolver.js";
import type { FitEvaluationRequest } from "./request.js";

export const PRODUCTION_EVALUATOR_NAME = "education-platform-fit-engine";
export const PRODUCTION_EVALUATOR_VERSION = "0.1.0";

type EvaluationRow = { evaluation_id: string; evaluation_as_of: string; evaluation_state: string };

export type ExecutedFitEvaluation = Readonly<{
  evaluationId: string;
  candidateInputFingerprint: string;
  resultFingerprint: string;
  output: FitEvaluationOutput;
}>;

export async function executeFitEvaluation(
  database: FitDatabaseGateway,
  request: FitEvaluationRequest,
  sourceDatabase: FitDatabaseGateway = database,
): Promise<ExecutedFitEvaluation> {
  if (request.evidence.approvedFinancialNormalizationIds.length !== 0) {
    throw new FitAdapterError("Reviewed Financial normalizations must resume their existing BUILDING evaluation", 400);
  }
  const contract = await resolveFitContract(sourceDatabase, {
    evaluatorName: PRODUCTION_EVALUATOR_NAME,
    evaluatorVersion: PRODUCTION_EVALUATOR_VERSION,
  });
  const evaluationId = await database.rpc<string>("start_fit_evaluation", {
    p_profile_version_id: request.profileVersionId,
    p_intent_set_id: request.intentSetId,
    p_program_version_id: request.programVersionId,
    p_taxonomy_release_code: request.taxonomyReleaseCode,
    p_contract_release_id: contract.release.id,
    p_evaluator_build_id: contract.evaluatorBuild.id,
    p_supersedes_evaluation_id: request.supersedesEvaluationId,
    p_eligibility_context_evaluation_id: request.eligibilityContextEvaluationId,
  });
  try {
    const evaluation = requireOne(await database.select<EvaluationRow>("fit_evaluations", {
      select: "evaluation_id,evaluation_as_of,evaluation_state",
      evaluation_id: `eq.${evaluationId}`,
    }), "started Fit evaluation");
    if (evaluation.evaluation_state !== "BUILDING") throw new FitAdapterError("New Fit evaluation is not BUILDING", 409);
    const input = canonicalizeFitEvaluationInput(await resolveFitEvaluationInput(
      sourceDatabase,
      contract,
      request,
      evaluation.evaluation_as_of,
    ));
    const output = evaluateFit(input);
    canonicalFitOutputJson(output);
    const fingerprints = await persistFitEvaluation(database, evaluationId, input, output);
    return { evaluationId, ...fingerprints, output };
  } catch (error) {
    if (error instanceof FitAdapterError) {
      throw new FitAdapterError(error.message, error.status, { evaluationId, detail: error.detail });
    }
    throw new FitAdapterError("Fit evaluation failed closed", 500, {
      evaluationId,
      cause: error instanceof Error ? error.message : String(error),
    });
  }
}
