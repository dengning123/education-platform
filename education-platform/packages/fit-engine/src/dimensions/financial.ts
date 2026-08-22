import type {
  DecisionManifestItem,
  FinancialComparable,
  FitEvaluationInput,
  FitSignal,
} from "../contracts.js";
import { compareText } from "../canonicalize.js";
import { compareExactDecimal } from "../decimal.js";
import {
  dimensionContext,
  finalizeDimension,
  intentItems,
  makeSignal,
  requiredInputUnknown,
  unknownDecision,
} from "./shared.js";

function comparableMatchesIntent(
  comparable: FinancialComparable,
  intent: Extract<
    Extract<DecisionManifestItem, { kind: "FIT_INTENT" }>["intent"],
    { kind: "FINANCIAL_CONSTRAINT" }
  >,
): boolean {
  return (
    comparable.currency === intent.currency &&
    comparable.period === intent.period &&
    comparable.scope === intent.scope &&
    comparable.basis === intent.basis &&
    [...comparable.components].sort(compareText).join("\u0000") ===
      [...intent.components].sort(compareText).join("\u0000")
  );
}

export function evaluateFinancial(input: FitEvaluationInput) {
  const context = dimensionContext(input, "FINANCIAL");
  const requiredUnknown = requiredInputUnknown(context);
  if (requiredUnknown !== null) return requiredUnknown;
  const intents = intentItems(context).filter(
    (item) =>
      item.intent.kind === "FINANCIAL_CONSTRAINT" &&
      item.intent.semantics !== "AVAILABLE_FUNDING",
  );
  if (intents.length === 0) return unknownDecision(context, "STUDENT_PREFERENCE_UNSPECIFIED");
  const direct = context.items.filter(
    (item): item is Extract<DecisionManifestItem, { kind: "DIRECT_FINANCIAL_COMPARABLE" }> =>
      item.kind === "DIRECT_FINANCIAL_COMPARABLE",
  );
  const normalized = context.items.filter(
    (item): item is Extract<
      DecisionManifestItem,
      { kind: "APPROVED_FINANCIAL_NORMALIZATION" }
    > => item.kind === "APPROVED_FINANCIAL_NORMALIZATION",
  );
  const signals: FitSignal[] = [];
  let usedNormalization = false;
  for (const intentItem of intents) {
    if (intentItem.intent.kind !== "FINANCIAL_CONSTRAINT") continue;
    const candidates: readonly Readonly<{
      item: (typeof direct)[number] | (typeof normalized)[number];
      comparable: FinancialComparable;
      normalized: boolean;
    }>[] = [
      ...direct
        .filter((item) => item.financialConstraintIntentId === intentItem.intent.intentId)
        .map((item) => ({ item, comparable: item.comparable, normalized: false })),
      ...normalized
        .filter((item) => item.financialConstraintIntentId === intentItem.intent.intentId)
        .map((item) => ({ item, comparable: item.target, normalized: true })),
    ];
    if (candidates.length !== 1) {
      return unknownDecision(
        context,
        "FINANCIAL_INPUTS_INCOMPARABLE",
        [intentItem.ref.manifestItemKey, ...candidates.map(({ item }) => item.ref.manifestItemKey)],
      );
    }
    const candidate = candidates[0];
    if (candidate === undefined || !comparableMatchesIntent(candidate.comparable, intentItem.intent)) {
      return unknownDecision(
        context,
        "FINANCIAL_INPUTS_INCOMPARABLE",
        [intentItem.ref.manifestItemKey, ...(candidate === undefined ? [] : [candidate.item.ref.manifestItemKey])],
      );
    }
    usedNormalization ||= candidate.normalized;
    const supports = compareExactDecimal(candidate.comparable.amount, intentItem.intent.amount) <= 0;
    const isHard =
      intentItem.intent.semantics === "HARD_TOTAL_COST_CEILING" ||
      intentItem.intent.semantics === "HARD_TUITION_CEILING";
    signals.push(
      makeSignal(context, {
        code: supports ? "MATERIAL_SUPPORT" : "MATERIAL_CONTRADICTION",
        direction: supports ? "SUPPORTING" : "CONTRADICTING",
        material: true,
        inferenceCategory: "DETERMINISTIC",
        evidence: [candidate.item],
        intent: intentItem,
        inputPolicyRegistryIds: [candidate.item.ref.inputPolicyRegistryId],
        requiredConstraintContradiction:
          !supports && isHard && intentItem.intent.authority.importance === "REQUIRED",
      }),
    );
  }
  return finalizeDimension(context, {
    signals,
    confidence: usedNormalization ? "MEDIUM" : "HIGH",
    coverage: "SUFFICIENT",
  });
}
