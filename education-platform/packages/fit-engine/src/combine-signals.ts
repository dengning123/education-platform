import type { FitAssessment } from "./contracts.js";

export type SignalPrecedenceFacts = Readonly<{
  hasMaterialSupport: boolean;
  hasMaterialContradiction: boolean;
  hasRequiredConstraintContradiction: boolean;
  hasQualifiedStrongAlignment: boolean;
  hasDirectionalBasis: boolean;
}>;

export function combineSignals(facts: SignalPrecedenceFacts): FitAssessment {
  if (facts.hasQualifiedStrongAlignment && !facts.hasMaterialSupport) {
    throw new Error("Qualified strong alignment requires material support");
  }
  if (facts.hasRequiredConstraintContradiction && !facts.hasMaterialContradiction) {
    throw new Error("A required contradiction must be material");
  }
  const hasDirection =
    facts.hasMaterialSupport ||
    facts.hasMaterialContradiction ||
    facts.hasQualifiedStrongAlignment;
  if (hasDirection !== facts.hasDirectionalBasis) {
    throw new Error("Directional basis projection is inconsistent");
  }
  if (facts.hasRequiredConstraintContradiction) return "MISALIGNMENT";
  if (facts.hasMaterialSupport && facts.hasMaterialContradiction) return "MIXED";
  if (facts.hasMaterialContradiction) return "MISALIGNMENT";
  if (facts.hasQualifiedStrongAlignment && facts.hasMaterialSupport) {
    return "STRONG_ALIGNMENT";
  }
  if (facts.hasMaterialSupport) return "ALIGNMENT";
  return "UNKNOWN";
}
