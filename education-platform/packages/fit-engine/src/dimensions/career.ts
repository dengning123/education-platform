import type { DecisionManifestItem, FitEvaluationInput, FitSignal } from "../contracts.js";
import {
  dimensionContext,
  finalizeDimension,
  intentItems,
  makeSignal,
  requiredInputUnknown,
  unknownDecision,
} from "./shared.js";

export function evaluateCareer(input: FitEvaluationInput) {
  const context = dimensionContext(input, "CAREER");
  const requiredUnknown = requiredInputUnknown(context);
  if (requiredUnknown !== null) return requiredUnknown;
  const intents = intentItems(context).filter(
    (item) => item.intent.kind === "TAXONOMY_TARGET",
  );
  if (intents.length === 0) return unknownDecision(context, "STUDENT_PREFERENCE_UNSPECIFIED");
  const mappings = context.items.filter(
    (item): item is Extract<DecisionManifestItem, { kind: "VERIFIED_MAPPING" }> =>
      item.kind === "VERIFIED_MAPPING" &&
      ["CAREER_ASSOCIATION", "INDUSTRY_ASSOCIATION", "PROGRAM_RELATED_TO_CAREER"].includes(
        item.relation,
      ),
  );
  const signals: FitSignal[] = [];
  let unmatched = false;
  for (const intent of intents) {
    if (intent.intent.kind !== "TAXONOMY_TARGET") continue;
    const conceptId = intent.intent.conceptId;
    const matches = mappings.filter((mapping) => mapping.conceptId === conceptId);
    if (matches.length === 0) {
      unmatched = true;
      continue;
    }
    for (const mapping of matches) {
      const supports = intent.intent.relation === "DESIRED";
      const relationPolicy = context.method.mappingRelations.find(
        (candidate) => candidate.relationRegistryId === mapping.relationRegistryId,
      );
      if (
        relationPolicy === undefined ||
        !relationPolicy.allowedAssessments.includes(
          supports ? "ALIGNMENT" : "MISALIGNMENT",
        )
      ) {
        unmatched = true;
        continue;
      }
      signals.push(
        makeSignal(context, {
          code: supports ? "MATERIAL_SUPPORT" : "MATERIAL_CONTRADICTION",
          direction: supports ? "SUPPORTING" : "CONTRADICTING",
          material: true,
          inferenceCategory: "REVIEWED_MAPPING",
          evidence: [mapping],
          intent,
          inputPolicyRegistryIds: [mapping.ref.inputPolicyRegistryId],
          mappingRelationRegistryId: mapping.relationRegistryId,
          requiredConstraintContradiction:
            !supports && intent.intent.authority.importance === "REQUIRED",
        }),
      );
    }
  }
  if (signals.length === 0) {
    return unknownDecision(
      context,
      unmatched ? "NO_AUTHORITATIVE_MAPPING" : "EVIDENCE_INSUFFICIENT",
      intents.map((item) => item.ref.manifestItemKey),
    );
  }
  return finalizeDimension(context, {
    signals,
    confidence: "MEDIUM",
    coverage: unmatched ? "PARTIAL" : "SUFFICIENT",
  });
}
