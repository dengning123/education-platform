import {
  type DecisionManifestItem,
  type DimensionDecision,
  type FitAssessment,
  type FitConfidence,
  type FitCoverage,
  type FitDimension,
  type FitEvaluationInput,
  type FitInputState,
  type FitReason,
  type FitReasonCode,
  type FitSignal,
  type FitSignalCode,
  type InferenceCategory,
  type LimitingInput,
  type ResolvedMethodContract,
} from "../contracts.js";
import {
  canonicalLimitingInputs,
  canonicalReasons,
  canonicalSignals,
  compareText,
} from "../canonicalize.js";
import { combineSignals } from "../combine-signals.js";
import { detectInputStateFacts } from "../coverage.js";
import { detectDirectionalSignalFacts } from "../confidence.js";
import {
  limitingInput,
  limitingReason,
  reasonForSignal,
  reasonForUnavailableState,
} from "../reasons.js";

export type DimensionContext<D extends FitDimension> = Readonly<{
  input: FitEvaluationInput;
  dimension: D;
  method: ResolvedMethodContract;
  methodInput: FitEvaluationInput["methods"][D];
  items: readonly DecisionManifestItem[];
  states: readonly FitInputState[];
}>;

export function dimensionContext<D extends FitDimension>(
  input: FitEvaluationInput,
  dimension: D,
): DimensionContext<D> {
  const method = input.resolvedContract.methods[dimension];
  return {
    input,
    dimension,
    method,
    methodInput: input.methods[dimension],
    items: input.manifest.filter((item) => item.ref.methodRegistryId === method.identity.id),
    states: input.inputStates.filter((state) => state.methodRegistryId === method.identity.id),
  };
}

export function intentItems<D extends FitDimension>(context: DimensionContext<D>) {
  return context.items.filter(
    (item): item is Extract<DecisionManifestItem, { kind: "FIT_INTENT" }> =>
      item.kind === "FIT_INTENT" && item.intent.dimension === context.dimension,
  );
}

export type SignalSpec = Readonly<{
  code: FitSignalCode;
  direction: "SUPPORTING" | "CONTRADICTING" | "LIMITING";
  material: boolean;
  inferenceCategory: InferenceCategory;
  evidence: readonly DecisionManifestItem[];
  intent: Extract<DecisionManifestItem, { kind: "FIT_INTENT" }> | null;
  inputPolicyRegistryIds: readonly string[];
  mappingRelationRegistryId?: string | null;
  requiredConstraintContradiction?: boolean;
  internationalHighImpact?: boolean;
}>;

export function makeSignal<D extends FitDimension>(
  context: DimensionContext<D>,
  spec: SignalSpec,
): FitSignal {
  const registered = context.method.signalTypes.find(
    (candidate) =>
      candidate.identity.code === spec.code &&
      candidate.direction === spec.direction &&
      candidate.material === spec.material,
  );
  if (registered === undefined) throw new Error(`Signal ${spec.code} is not registered for ${context.dimension}`);
  if (!registered.allowedInferenceCategories.includes(spec.inferenceCategory)) {
    throw new Error(`Signal ${spec.code} does not permit ${spec.inferenceCategory}`);
  }
  const relationId = spec.mappingRelationRegistryId ?? null;
  if (
    relationId !== null &&
    !context.method.mappingRelations.some((relation) => relation.relationRegistryId === relationId)
  ) {
    throw new Error("Signal uses an unregistered mapping relation");
  }
  return {
    methodRegistryId: context.method.identity.id,
    signalTypeRegistryId: registered.identity.id,
    inputPolicyRegistryIds: [...spec.inputPolicyRegistryIds].sort(compareText),
    mappingRelationRegistryId: relationId,
    signalCode: spec.code,
    direction: spec.direction,
    material: spec.material,
    inferenceCategory: spec.inferenceCategory,
    evidenceManifestRefs: spec.evidence
      .map((item) => item.ref.manifestItemKey)
      .sort(compareText),
    intentManifestRef: spec.intent?.ref.manifestItemKey ?? null,
    requiredConstraintContradiction:
      spec.requiredConstraintContradiction ?? false,
    internationalHighImpact: spec.internationalHighImpact ?? false,
    model: null,
  };
}

type DecisionSpec = Readonly<{
  signals?: readonly FitSignal[];
  customLimitingReasons?: readonly Readonly<{
    code: FitReasonCode;
    refs: readonly string[];
    state?: FitInputState;
  }>[];
  limitingStates?: readonly FitInputState[];
  confidence: FitConfidence;
  coverage: FitCoverage;
  qualifiedStrongAlignment?: boolean;
}>;

export function finalizeDimension<D extends FitDimension>(
  context: DimensionContext<D>,
  spec: DecisionSpec,
): DimensionDecision<D> {
  const signals = canonicalSignals(spec.signals ?? []);
  const hasMaterialSupport = signals.some(
    (signal) => signal.material && signal.direction === "SUPPORTING",
  );
  const hasMaterialContradiction = signals.some(
    (signal) => signal.material && signal.direction === "CONTRADICTING",
  );
  const hasRequiredConstraintContradiction = signals.some(
    (signal) => signal.requiredConstraintContradiction,
  );
  const hasQualifiedStrongAlignment = spec.qualifiedStrongAlignment ?? false;
  if (hasQualifiedStrongAlignment) {
    if (!context.method.permitsStrongAlignment) throw new Error("Method forbids strong alignment");
    if (
      !signals.some((signal) => {
        const registered = context.method.signalTypes.find(
          (candidate) => candidate.identity.id === signal.signalTypeRegistryId,
        );
        return registered?.permitsStrongAlignment === true;
      })
    ) {
      throw new Error("No registered signal qualifies strong alignment");
    }
  }
  const assessment = combineSignals({
    hasMaterialSupport,
    hasMaterialContradiction,
    hasRequiredConstraintContradiction,
    hasQualifiedStrongAlignment,
    hasDirectionalBasis: hasMaterialSupport || hasMaterialContradiction,
  });
  for (const signal of signals) {
    if (signal.mappingRelationRegistryId === null) continue;
    const relation = context.method.mappingRelations.find(
      (candidate) => candidate.relationRegistryId === signal.mappingRelationRegistryId,
    );
    if (relation === undefined || !relation.allowedAssessments.includes(assessment)) {
      throw new Error("Mapping relation does not authorize the resulting assessment");
    }
  }
  const directionalFacts = detectDirectionalSignalFacts(signals);
  if (directionalFacts.hasModelMaterialDirection && spec.confidence === "HIGH") {
    throw new Error("Material model involvement caps confidence below HIGH");
  }
  if (
    directionalFacts.isModelOnlyDirection &&
    (assessment !== "UNKNOWN" || spec.confidence !== "LOW")
  ) {
    throw new Error("Model-only direction must fail closed");
  }
  if (spec.coverage === "INSUFFICIENT" && assessment !== "UNKNOWN") {
    throw new Error("INSUFFICIENT coverage permits only UNKNOWN");
  }
  if (assessment === "UNKNOWN" && signals.some((signal) => signal.material)) {
    throw new Error("UNKNOWN cannot retain a material directional signal");
  }
  const reasons: FitReason[] = signals
    .filter((signal) => signal.material)
    .map((signal) => reasonForSignal(
      context.input.resolvedContract,
      context.dimension,
      assessment,
      signal,
    ));
  for (const item of spec.customLimitingReasons ?? []) {
    reasons.push(
      limitingReason(
        context.input.resolvedContract,
        context.dimension,
        context.method.identity.id,
        assessment,
        item.code,
        item.refs,
        item.state ?? null,
      ),
    );
  }
  const limitingInputs: LimitingInput[] = [];
  for (const state of spec.limitingStates ?? []) {
    reasons.push(
      reasonForUnavailableState(
        context.input.resolvedContract,
        context.dimension,
        state,
        assessment,
      ),
    );
    limitingInputs.push(
      limitingInput(
        context.input.resolvedContract,
        context.dimension,
        state,
        assessment,
      ),
    );
  }
  if (reasons.length === 0) throw new Error(`Dimension ${context.dimension} requires a structured reason`);
  const exactManifestRefs = new Set<string>();
  for (const signal of signals) {
    signal.evidenceManifestRefs.forEach((value) => exactManifestRefs.add(value));
    if (signal.intentManifestRef !== null) exactManifestRefs.add(signal.intentManifestRef);
  }
  for (const reason of reasons) reason.exactManifestRefs.forEach((value) => exactManifestRefs.add(value));
  for (const limiting of limitingInputs) {
    if (limiting.completenessManifestRef !== null) exactManifestRefs.add(limiting.completenessManifestRef);
    if (limiting.provenanceManifestRef !== null) exactManifestRefs.add(limiting.provenanceManifestRef);
  }
  const methodCode = context.methodInput.methodCode as DimensionDecision<D>["methodCode"];
  return {
    dimension: context.dimension,
    methodRegistryId: context.method.identity.id,
    methodCode,
    methodVersion: 1,
    assessment,
    confidence: spec.confidence,
    evidenceCoverage: spec.coverage,
    inferenceCategory: context.methodInput.inferenceCategory,
    signals,
    reasons: canonicalReasons(reasons),
    limitingInputs: canonicalLimitingInputs(limitingInputs),
    exactManifestRefs: [...exactManifestRefs].sort(compareText),
  };
}

export function requiredInputUnknown<D extends FitDimension>(
  context: DimensionContext<D>,
): DimensionDecision<D> | null {
  const facts = detectInputStateFacts(context.states);
  if (facts.requiredUnavailable.length === 0) return null;
  return finalizeDimension(context, {
    confidence: "LOW",
    coverage: "INSUFFICIENT",
    limitingStates: facts.requiredUnavailable,
  });
}

export function unknownDecision<D extends FitDimension>(
  context: DimensionContext<D>,
  code: FitReasonCode,
  refs: readonly string[] = [],
  coverage: FitCoverage = "INSUFFICIENT",
): DimensionDecision<D> {
  return finalizeDimension(context, {
    confidence: "LOW",
    coverage,
    customLimitingReasons: [{ code, refs }],
  });
}
