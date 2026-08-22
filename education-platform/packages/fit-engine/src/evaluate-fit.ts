import type { FitEvaluationInput, FitEvaluationOutput } from "./contracts.js";
import { canonicalizeFitInput, canonicalJson, deepFreeze } from "./canonicalize.js";
import { evaluateAcademic } from "./dimensions/academic.js";
import { evaluateCareer } from "./dimensions/career.js";
import { evaluateFinancial } from "./dimensions/financial.js";
import { evaluateGeographicDelivery } from "./dimensions/geographic-delivery.js";
import { evaluateInternationalAccessibility } from "./dimensions/international-accessibility.js";
import { evaluatePersonalPreference } from "./dimensions/personal-preference.js";
import { validateFitInput } from "./validate-contract.js";

export function canonicalizeFitEvaluationInput(
  input: FitEvaluationInput,
): FitEvaluationInput {
  const canonical = canonicalizeFitInput(input);
  validateFitInput(canonical);
  return deepFreeze(canonical);
}

export function canonicalFitInputJson(input: FitEvaluationInput): string {
  return canonicalJson(canonicalizeFitEvaluationInput(input));
}

export function evaluateFit(input: FitEvaluationInput): FitEvaluationOutput {
  const canonical = canonicalizeFitEvaluationInput(input);
  const output: FitEvaluationOutput = {
    schemaVersion: "fit-v0.1",
    dimensions: {
      ACADEMIC: evaluateAcademic(canonical),
      CAREER: evaluateCareer(canonical),
      FINANCIAL: evaluateFinancial(canonical),
      GEOGRAPHIC_DELIVERY: evaluateGeographicDelivery(canonical),
      PERSONAL_PREFERENCE: evaluatePersonalPreference(canonical),
      INTERNATIONAL_ACCESSIBILITY: evaluateInternationalAccessibility(canonical),
    },
  };
  return deepFreeze(output);
}

export function canonicalFitOutputJson(output: FitEvaluationOutput): string {
  return canonicalJson(output);
}
