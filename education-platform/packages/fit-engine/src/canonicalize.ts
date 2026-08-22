import {
  FIT_DIMENSIONS,
  type DecisionManifestItem,
  type FitEvaluationInput,
  type FitInputState,
  type FitReason,
  type FitSignal,
  type LimitingInput,
  type ResolvedFitContract,
  type ResolvedMethodContract,
} from "./contracts.js";

export function compareText(left: string, right: string): number {
  return left < right ? -1 : left > right ? 1 : 0;
}

function sorted<T>(values: readonly T[], key: (value: T) => string): readonly T[] {
  return [...values].sort((left, right) => compareText(key(left), key(right)));
}

function canonicalManifestItem(item: DecisionManifestItem): DecisionManifestItem {
  if (item.kind === "FIT_INTENT" && item.intent.kind === "FINANCIAL_CONSTRAINT") {
    return {
      ...item,
      intent: { ...item.intent, components: [...item.intent.components].sort(compareText) },
    };
  }
  if (item.kind === "DIRECT_FINANCIAL_COMPARABLE") {
    return {
      ...item,
      comparable: {
        ...item.comparable,
        components: [...item.comparable.components].sort(compareText),
      },
    };
  }
  if (item.kind === "APPROVED_FINANCIAL_NORMALIZATION") {
    return {
      ...item,
      source: { ...item.source, components: [...item.source.components].sort(compareText) },
      target: { ...item.target, components: [...item.target.components].sort(compareText) },
    };
  }
  if (
    item.kind === "HISTORICAL_CONTEXT_SELECTION" &&
    item.value?.claimCode === "CITIZENSHIP_SECURITY_CLEARANCE_RESTRICTION"
  ) {
    return {
      ...item,
      value: { ...item.value, citizenships: [...item.value.citizenships].sort(compareText) },
    };
  }
  return item;
}

function canonicalMethod(method: ResolvedMethodContract): ResolvedMethodContract {
  return {
    ...method,
    sourceClassPolicies: sorted(
      method.sourceClassPolicies,
      (value) => `${value.sourceClassCode}\u0000${value.disposition}`,
    ),
    inputPolicies: sorted(method.inputPolicies, (value) => value.identity.id).map(
      (policy) => ({
        ...policy,
        programFields: sorted(
          policy.programFields,
          (value) => `${value.recordType}\u0000${value.fieldName}`,
        ),
      }),
    ),
    mappingRelations: sorted(method.mappingRelations, (value) => value.relationRegistryId).map(
      (relation) => ({
        ...relation,
        allowedAssessments: [...relation.allowedAssessments].sort(compareText),
      }),
    ),
    signalTypes: sorted(method.signalTypes, (value) => value.identity.id).map((signal) => ({
      ...signal,
      allowedInferenceCategories: [...signal.allowedInferenceCategories].sort(compareText),
    })),
  };
}

function canonicalContract(contract: ResolvedFitContract): ResolvedFitContract {
  return {
    ...contract,
    semanticSourceClasses: sorted(
      contract.semanticSourceClasses,
      (value) => value.sourceClassRegistryId,
    ),
    mappingRelationDefinitions: sorted(
      contract.mappingRelationDefinitions,
      (value) => value.relationRegistryId,
    ),
    methods: {
      ACADEMIC: canonicalMethod(contract.methods.ACADEMIC),
      CAREER: canonicalMethod(contract.methods.CAREER),
      FINANCIAL: canonicalMethod(contract.methods.FINANCIAL),
      GEOGRAPHIC_DELIVERY: canonicalMethod(contract.methods.GEOGRAPHIC_DELIVERY),
      PERSONAL_PREFERENCE: canonicalMethod(contract.methods.PERSONAL_PREFERENCE),
      INTERNATIONAL_ACCESSIBILITY: canonicalMethod(
        contract.methods.INTERNATIONAL_ACCESSIBILITY,
      ),
    },
    reasons: sorted(contract.reasons, (value) => value.identity.id).map((reason) => ({
      ...reason,
      allowedAssessments: [...reason.allowedAssessments].sort(compareText),
    })),
    financialNormalizations: sorted(
      contract.financialNormalizations,
      (value) => value.identity.id,
    ),
  };
}

function canonicalInputState(state: FitInputState): FitInputState {
  return { ...state, manifestItemKeys: [...state.manifestItemKeys].sort(compareText) };
}

export function canonicalizeFitInput(input: FitEvaluationInput): FitEvaluationInput {
  return {
    ...input,
    resolvedContract: canonicalContract(input.resolvedContract),
    methods: {
      ACADEMIC: { ...input.methods.ACADEMIC },
      CAREER: { ...input.methods.CAREER },
      FINANCIAL: { ...input.methods.FINANCIAL },
      GEOGRAPHIC_DELIVERY: { ...input.methods.GEOGRAPHIC_DELIVERY },
      PERSONAL_PREFERENCE: { ...input.methods.PERSONAL_PREFERENCE },
      INTERNATIONAL_ACCESSIBILITY: { ...input.methods.INTERNATIONAL_ACCESSIBILITY },
    },
    manifest: sorted(
      input.manifest.map(canonicalManifestItem),
      (item) => item.ref.manifestItemKey,
    ),
    inputStates: sorted(
      input.inputStates.map(canonicalInputState),
      (state) => `${state.methodRegistryId}\u0000${state.inputPolicyRegistryId}`,
    ),
  };
}

export function canonicalSignals(signals: readonly FitSignal[]): readonly FitSignal[] {
  return sorted(
    signals.map((signal) => ({
      ...signal,
      inputPolicyRegistryIds: [...signal.inputPolicyRegistryIds].sort(compareText),
      evidenceManifestRefs: [...signal.evidenceManifestRefs].sort(compareText),
    })),
    (signal) =>
      `${signal.signalTypeRegistryId}\u0000${signal.intentManifestRef ?? ""}\u0000${signal.evidenceManifestRefs.join("\u0000")}`,
  );
}

export function canonicalReasons(reasons: readonly FitReason[]): readonly FitReason[] {
  return sorted(
    reasons.map((reason) => ({
      ...reason,
      exactManifestRefs: [...reason.exactManifestRefs].sort(compareText),
    })),
    (reason) =>
      `${reason.reasonDefinitionRegistryId}\u0000${reason.signalTypeRegistryId ?? ""}\u0000${reason.inputPolicyRegistryId ?? ""}`,
  );
}

export function canonicalLimitingInputs(
  inputs: readonly LimitingInput[],
): readonly LimitingInput[] {
  return sorted(
    inputs,
    (input) => `${input.inputPolicyRegistryId}\u0000${input.availability}`,
  );
}

function jsonReady(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(jsonReady);
  if (value !== null && typeof value === "object") {
    const entries = Object.entries(value).sort(([left], [right]) => compareText(left, right));
    const result: { [key: string]: unknown } = {};
    for (const [key, child] of entries) result[key] = jsonReady(child);
    return result;
  }
  return value;
}

export function canonicalJson(value: unknown): string {
  return JSON.stringify(jsonReady(value));
}

export function deepFreeze<T>(value: T): T {
  if (value !== null && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const child of Object.values(value)) deepFreeze(child);
  }
  return value;
}

export function assertDimensionOrder(value: readonly string[]): void {
  if (value.length !== FIT_DIMENSIONS.length) throw new Error("Exactly six dimensions are required");
  for (let index = 0; index < FIT_DIMENSIONS.length; index += 1) {
    if (value[index] !== FIT_DIMENSIONS[index]) throw new Error("Dimension order is not canonical");
  }
}
