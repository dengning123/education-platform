import type {
  FitAssessment,
  FitDimension,
  FitInputState,
  FitReason,
  FitReasonCode,
  FitSignal,
  LimitingInput,
  ResolvedFitContract,
} from "./contracts.js";
import { availabilityReason } from "./coverage.js";

function resolveReason(
  contract: ResolvedFitContract,
  dimension: FitDimension,
  code: FitReasonCode,
  assessment: FitAssessment,
) {
  const reason = contract.reasons.find(
    (candidate) =>
      candidate.identity.code === code &&
      (candidate.dimension === null || candidate.dimension === dimension),
  );
  if (reason === undefined) throw new Error(`Reason ${code} is absent from the resolved registry`);
  if (!reason.allowedAssessments.includes(assessment)) {
    throw new Error(`Reason ${code} is incompatible with ${assessment}`);
  }
  return reason;
}

export function reasonForSignal(
  contract: ResolvedFitContract,
  dimension: FitDimension,
  assessment: FitAssessment,
  signal: FitSignal,
): FitReason {
  const code: FitReasonCode = signal.requiredConstraintContradiction
    ? "REQUIRED_CONSTRAINT_CONTRADICTED"
    : signal.direction === "SUPPORTING"
      ? "MATERIAL_EVIDENCE_SUPPORTS_ALIGNMENT"
      : signal.direction === "CONTRADICTING"
        ? "MATERIAL_EVIDENCE_CONTRADICTS_INTENT"
        : "EVIDENCE_INSUFFICIENT";
  const definition = resolveReason(contract, dimension, code, assessment);
  return {
    methodRegistryId: signal.methodRegistryId,
    reasonDefinitionRegistryId: definition.identity.id,
    reasonCode: code,
    direction: definition.direction,
    signalCode: signal.signalCode,
    signalTypeRegistryId: signal.signalTypeRegistryId,
    inputPolicyKey: null,
    inputPolicyRegistryId: signal.inputPolicyRegistryIds[0] ?? null,
    mappingRelationRegistryId: signal.mappingRelationRegistryId,
    exactManifestRefs: [
      ...signal.evidenceManifestRefs,
      ...(signal.intentManifestRef === null ? [] : [signal.intentManifestRef]),
    ],
  };
}

export function limitingReason(
  contract: ResolvedFitContract,
  dimension: FitDimension,
  methodRegistryId: string,
  assessment: FitAssessment,
  code: FitReasonCode,
  exactManifestRefs: readonly string[],
  state: FitInputState | null = null,
): FitReason {
  const definition = resolveReason(contract, dimension, code, assessment);
  return {
    methodRegistryId,
    reasonDefinitionRegistryId: definition.identity.id,
    reasonCode: code,
    direction: definition.direction,
    signalCode: null,
    signalTypeRegistryId: null,
    inputPolicyKey: state?.policyKey ?? null,
    inputPolicyRegistryId: state?.inputPolicyRegistryId ?? null,
    mappingRelationRegistryId: null,
    exactManifestRefs,
  };
}

export function limitingInput(
  contract: ResolvedFitContract,
  dimension: FitDimension,
  state: FitInputState,
  assessment: FitAssessment,
): LimitingInput {
  if (state.availability === "INCLUDED") throw new Error("INCLUDED input is not limiting");
  const code = availabilityReason(state.availability);
  const definition = resolveReason(contract, dimension, code, assessment);
  return {
    methodRegistryId: state.methodRegistryId,
    reasonCode: code,
    reasonDefinitionRegistryId: definition.identity.id,
    inputPolicyKey: state.policyKey,
    inputPolicyRegistryId: state.inputPolicyRegistryId,
    availability: state.availability,
    completenessManifestRef: state.completenessManifestItemKey,
    provenanceManifestRef: state.provenanceManifestItemKey,
  };
}

export function reasonForUnavailableState(
  contract: ResolvedFitContract,
  dimension: FitDimension,
  state: FitInputState,
  assessment: FitAssessment,
): FitReason {
  if (state.availability === "INCLUDED") throw new Error("INCLUDED input is not limiting");
  const refs = [state.completenessManifestItemKey, state.provenanceManifestItemKey].filter(
    (value): value is string => value !== null,
  );
  return limitingReason(
    contract,
    dimension,
    state.methodRegistryId,
    assessment,
    availabilityReason(state.availability),
    refs,
    state,
  );
}
