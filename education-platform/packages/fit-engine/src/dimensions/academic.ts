import type { DecisionManifestItem, FitEvaluationInput, FitSignal } from "../contracts.js";
import {
  dimensionContext,
  finalizeDimension,
  intentItems,
  makeSignal,
  requiredInputUnknown,
  unknownDecision,
} from "./shared.js";

export function evaluateAcademic(input: FitEvaluationInput) {
  const context = dimensionContext(input, "ACADEMIC");
  const requiredUnknown = requiredInputUnknown(context);
  if (requiredUnknown !== null) return requiredUnknown;
  const intents = intentItems(context).filter(
    (item) => item.intent.kind === "TAXONOMY_TARGET",
  );
  if (intents.length === 0) return unknownDecision(context, "STUDENT_PREFERENCE_UNSPECIFIED");
  const mappings = context.items.filter(
    (item): item is Extract<DecisionManifestItem, { kind: "VERIFIED_MAPPING" }> =>
      item.kind === "VERIFIED_MAPPING",
  );
  const courses = context.items.filter(
    (item): item is Extract<DecisionManifestItem, { kind: "CANONICAL_PROGRAM_FACT" }> =>
      item.kind === "CANONICAL_PROGRAM_FACT" && item.fact.recordType === "PROGRAM_COURSE",
  );
  const signals: FitSignal[] = [];
  let unmatched = false;
  let qualifiedStrong = false;
  for (const intent of intents) {
    if (intent.intent.kind !== "TAXONOMY_TARGET") continue;
    const conceptId = intent.intent.conceptId;
    const matches = mappings.filter((mapping) => mapping.conceptId === conceptId);
    if (matches.length === 0) {
      unmatched = true;
      continue;
    }
    for (const mapping of matches) {
      const course = courses.find((candidate) => candidate.ref.sourceId === mapping.ref.sourceId);
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
      const highImportance =
        intent.intent.authority.importance === "REQUIRED" ||
        intent.intent.authority.importance === "STRONGLY_PREFERRED";
      const direct = supports && highImportance && course !== undefined;
      if (direct) qualifiedStrong = true;
      signals.push(
        makeSignal(context, {
          code: direct
            ? "DIRECT_HIGH_IMPORTANCE_AUTHORITATIVE_MATCH"
            : supports
              ? "MATERIAL_SUPPORT"
              : "MATERIAL_CONTRADICTION",
          direction: supports ? "SUPPORTING" : "CONTRADICTING",
          material: true,
          inferenceCategory: direct ? "DETERMINISTIC" : "REVIEWED_MAPPING",
          evidence: course === undefined ? [mapping] : [mapping, course],
          intent,
          inputPolicyRegistryIds: [mapping.ref.inputPolicyRegistryId],
          mappingRelationRegistryId: direct ? null : mapping.relationRegistryId,
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
    qualifiedStrongAlignment: qualifiedStrong,
    confidence: qualifiedStrong ? "HIGH" : "MEDIUM",
    coverage: unmatched ? "PARTIAL" : "SUFFICIENT",
  });
}
