import type { DecisionManifestItem, FitEvaluationInput, FitSignal } from "../contracts.js";
import {
  dimensionContext,
  finalizeDimension,
  intentItems,
  makeSignal,
  requiredInputUnknown,
  unknownDecision,
} from "./shared.js";

function currentAt(item: Extract<DecisionManifestItem, { kind: "HISTORICAL_CONTEXT_SELECTION" }>, asOf: string) {
  const at = Date.parse(asOf);
  return Date.parse(item.validFrom) <= at &&
    (item.validTo === null || at <= Date.parse(item.validTo));
}

export function evaluateInternationalAccessibility(input: FitEvaluationInput) {
  const context = dimensionContext(input, "INTERNATIONAL_ACCESSIBILITY");
  const requiredUnknown = requiredInputUnknown(context);
  if (requiredUnknown !== null) return requiredUnknown;
  const intents = intentItems(context).filter(
    (item) => item.intent.kind === "TAXONOMY_TARGET",
  );
  if (intents.length === 0) return unknownDecision(context, "STUDENT_PREFERENCE_UNSPECIFIED");
  const access = context.items.find(
    (item): item is Extract<DecisionManifestItem, { kind: "STUDENT_ACCESS_CONTEXT" }> =>
      item.kind === "STUDENT_ACCESS_CONTEXT",
  );
  if (access === undefined) {
    return unknownDecision(
      context,
      "REQUIRED_INPUT_UNAVAILABLE",
      intents.map((item) => item.ref.manifestItemKey),
    );
  }
  const mappings = context.items.filter(
    (item): item is Extract<DecisionManifestItem, { kind: "VERIFIED_MAPPING" }> =>
      item.kind === "VERIFIED_MAPPING" &&
      ["PROGRAM_ASSOCIATED_WITH_PATH", "CLAIM_APPLIES_TO_CONCEPT"].includes(item.relation),
  );
  const claims = context.items.filter(
    (item): item is Extract<
      DecisionManifestItem,
      { kind: "HISTORICAL_CONTEXT_SELECTION" }
    > =>
      item.kind === "HISTORICAL_CONTEXT_SELECTION" &&
      item.knowledgeStatus === "KNOWN" &&
      item.observationWorkflowStatusAtSelection === "VERIFIED" &&
      item.authority === "OFFICIAL_REGULATORY" &&
      item.value !== null &&
      currentAt(item, input.evaluationAsOf),
  );
  const signals: FitSignal[] = [];
  for (const intent of intents) {
    if (intent.intent.kind !== "TAXONOMY_TARGET") continue;
    const conceptId = intent.intent.conceptId;
    const relation = mappings.find((mapping) => mapping.conceptId === conceptId);
    const claim = claims.find(
      (candidate) =>
        (candidate.programVersionId === null || candidate.programVersionId === input.programVersionId) &&
        (candidate.jurisdictionCode === null ||
          candidate.jurisdictionCode === access.jurisdictionCode) &&
        (candidate.pathCode === null || candidate.pathCode === access.targetPathCode),
    );
    if (relation === undefined || claim === undefined || claim.value === null) {
      return unknownDecision(
        context,
        "INTERNATIONAL_EVIDENCE_INAPPLICABLE",
        [intent.ref.manifestItemKey, access.ref.manifestItemKey],
      );
    }
    const value = claim.value;
    const accessible =
      value.claimCode === "REGULATORY_WORK_AUTHORIZATION"
        ? value.allowed
        : value.claimCode === "JURISDICTION_PATH_ACCESSIBILITY"
          ? value.accessible
          : value.claimCode === "LICENSING_RESTRICTION" ||
              value.claimCode === "CITIZENSHIP_SECURITY_CLEARANCE_RESTRICTION"
            ? !value.restricted
            : undefined;
    if (accessible === undefined) {
      return unknownDecision(
        context,
        "INTERNATIONAL_EVIDENCE_INAPPLICABLE",
        [claim.ref.manifestItemKey],
      );
    }
    const supports = intent.intent.relation === "DESIRED" ? accessible : !accessible;
    signals.push(
      makeSignal(context, {
        code: supports ? "MATERIAL_SUPPORT" : "MATERIAL_CONTRADICTION",
        direction: supports ? "SUPPORTING" : "CONTRADICTING",
        material: true,
        inferenceCategory: "HYBRID",
        evidence: [claim, relation, access],
        intent,
        inputPolicyRegistryIds: [
          claim.ref.inputPolicyRegistryId,
          relation.ref.inputPolicyRegistryId,
          access.ref.inputPolicyRegistryId,
        ],
        mappingRelationRegistryId: relation.relationRegistryId,
        requiredConstraintContradiction:
          !supports && intent.intent.authority.importance === "REQUIRED",
        internationalHighImpact: true,
      }),
    );
  }
  return finalizeDimension(context, {
    signals,
    confidence: "HIGH",
    coverage: "SUFFICIENT",
  });
}
