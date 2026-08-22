import type { DecisionManifestItem, FitEvaluationInput, FitSignal } from "../contracts.js";
import {
  dimensionContext,
  finalizeDimension,
  intentItems,
  makeSignal,
  requiredInputUnknown,
  unknownDecision,
} from "./shared.js";

export function evaluateGeographicDelivery(input: FitEvaluationInput) {
  const context = dimensionContext(input, "GEOGRAPHIC_DELIVERY");
  const requiredUnknown = requiredInputUnknown(context);
  if (requiredUnknown !== null) return requiredUnknown;
  const intents = intentItems(context);
  if (intents.length === 0) return unknownDecision(context, "STUDENT_PREFERENCE_UNSPECIFIED");
  const locationIntents = intents.filter((item) => item.intent.kind === "LOCATION_CONSTRAINT");
  const deliveryIntents = intents.filter((item) => item.intent.kind === "DELIVERY_CONSTRAINT");
  const deliveryFact = context.items.find(
    (item): item is Extract<DecisionManifestItem, { kind: "CANONICAL_PROGRAM_FACT" }> =>
      item.kind === "CANONICAL_PROGRAM_FACT" &&
      item.fact.recordType === "PROGRAM_VERSION" &&
      item.fact.field === "delivery_mode" &&
      item.fact.value !== "UNKNOWN",
  );
  if (deliveryIntents.length === 0 || deliveryFact === undefined) {
    return unknownDecision(
      context,
      "PROGRAM_FACT_UNKNOWN",
      intents.map((item) => item.ref.manifestItemKey),
      locationIntents.length > 0 && deliveryFact !== undefined ? "PARTIAL" : "INSUFFICIENT",
    );
  }
  const signals: FitSignal[] = [];
  for (const intent of deliveryIntents) {
    if (intent.intent.kind !== "DELIVERY_CONSTRAINT") continue;
    const equal = deliveryFact.fact.value === intent.intent.deliveryMode;
    const supports = intent.intent.relation === "DESIRED" ? equal : !equal;
    const requiredContradiction =
      !supports && intent.intent.authority.importance === "REQUIRED";
    if (locationIntents.length > 0 && !requiredContradiction) continue;
    signals.push(
      makeSignal(context, {
        code: supports ? "MATERIAL_SUPPORT" : "MATERIAL_CONTRADICTION",
        direction: supports ? "SUPPORTING" : "CONTRADICTING",
        material: true,
        inferenceCategory: "DETERMINISTIC",
        evidence: [deliveryFact],
        intent,
        inputPolicyRegistryIds: [deliveryFact.ref.inputPolicyRegistryId],
        requiredConstraintContradiction: requiredContradiction,
      }),
    );
  }
  if (locationIntents.length > 0 && signals.length === 0) {
    return unknownDecision(
      context,
      "PROGRAM_FACT_UNKNOWN",
      [
        deliveryFact.ref.manifestItemKey,
        ...locationIntents.map((item) => item.ref.manifestItemKey),
      ],
      "PARTIAL",
    );
  }
  return finalizeDimension(context, {
    signals,
    confidence: locationIntents.length > 0 ? "MEDIUM" : "HIGH",
    coverage: locationIntents.length > 0 ? "PARTIAL" : "SUFFICIENT",
  });
}
