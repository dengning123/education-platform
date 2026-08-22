import type { DecisionManifestItem, FitEvaluationInput, FitSignal } from "../contracts.js";
import { compareExactDecimal } from "../decimal.js";
import {
  dimensionContext,
  finalizeDimension,
  intentItems,
  makeSignal,
  requiredInputUnknown,
  unknownDecision,
} from "./shared.js";

export function evaluatePersonalPreference(input: FitEvaluationInput) {
  const context = dimensionContext(input, "PERSONAL_PREFERENCE");
  const requiredUnknown = requiredInputUnknown(context);
  if (requiredUnknown !== null) return requiredUnknown;
  const intents = intentItems(context);
  if (intents.length === 0) return unknownDecision(context, "STUDENT_PREFERENCE_UNSPECIFIED");
  const facts = context.items.filter(
    (item): item is Extract<DecisionManifestItem, { kind: "CANONICAL_PROGRAM_FACT" }> =>
      item.kind === "CANONICAL_PROGRAM_FACT" && item.fact.recordType === "PROGRAM_VERSION",
  );
  const signals: FitSignal[] = [];
  for (const intent of intents) {
    let fact: (typeof facts)[number] | undefined;
    let supports: boolean | undefined;
    if (intent.intent.kind === "DURATION_CONSTRAINT") {
      fact = facts.find((candidate) => candidate.fact.field === "duration_months");
      if (fact !== undefined && fact.fact.field === "duration_months") {
        const aboveMinimum =
          intent.intent.minimumMonths === null ||
          compareExactDecimal(fact.fact.value, intent.intent.minimumMonths) >= 0;
        const belowMaximum =
          intent.intent.maximumMonths === null ||
          compareExactDecimal(fact.fact.value, intent.intent.maximumMonths) <= 0;
        supports = aboveMinimum && belowMaximum;
      }
    } else if (
      intent.intent.kind === "PROGRAM_FEATURE_CONSTRAINT" &&
      intent.intent.feature === "CAPSTONE_AVAILABLE"
    ) {
      fact = facts.find((candidate) => candidate.fact.field === "capstone_required");
      if (fact !== undefined && fact.fact.field === "capstone_required") {
        supports = fact.fact.value === intent.intent.expected;
      }
    } else {
      return unknownDecision(
        context,
        "PROGRAM_FACT_UNKNOWN",
        [intent.ref.manifestItemKey],
      );
    }
    if (fact === undefined || supports === undefined) {
      return unknownDecision(
        context,
        "PROGRAM_FACT_UNKNOWN",
        [intent.ref.manifestItemKey],
      );
    }
    signals.push(
      makeSignal(context, {
        code: supports ? "MATERIAL_SUPPORT" : "MATERIAL_CONTRADICTION",
        direction: supports ? "SUPPORTING" : "CONTRADICTING",
        material: true,
        inferenceCategory: "DETERMINISTIC",
        evidence: [fact],
        intent,
        inputPolicyRegistryIds: [fact.ref.inputPolicyRegistryId],
        requiredConstraintContradiction:
          !supports && intent.intent.authority.importance === "REQUIRED",
      }),
    );
  }
  return finalizeDimension(context, {
    signals,
    confidence: "HIGH",
    coverage: "SUFFICIENT",
  });
}
