import type { FitInputState, InputAvailability } from "./contracts.js";

export type InputStateFacts = Readonly<{
  requiredUnavailable: readonly FitInputState[];
  optionalUnavailable: readonly FitInputState[];
  included: readonly FitInputState[];
  hasSourceConflict: boolean;
  hasStaleSource: boolean;
}>;

export function detectInputStateFacts(states: readonly FitInputState[]): InputStateFacts {
  const unavailable = states.filter((state) => state.availability !== "INCLUDED");
  return {
    requiredUnavailable: unavailable.filter((state) => state.requirement === "REQUIRED"),
    optionalUnavailable: unavailable.filter((state) => state.requirement === "OPTIONAL"),
    included: states.filter((state) => state.availability === "INCLUDED"),
    hasSourceConflict: unavailable.some((state) => state.availability === "SOURCE_CONFLICT"),
    hasStaleSource: unavailable.some((state) => state.availability === "STALE_SOURCE"),
  };
}

export function availabilityReason(
  availability: Exclude<InputAvailability, "INCLUDED">,
): "SOURCE_CONFLICT" | "STALE_SOURCE" | "INPUT_INAPPLICABLE" | "STUDENT_INPUT_INCOMPLETE" | "REQUIRED_INPUT_UNAVAILABLE" {
  if (availability === "SOURCE_CONFLICT") return "SOURCE_CONFLICT";
  if (availability === "STALE_SOURCE") return "STALE_SOURCE";
  if (availability === "INAPPLICABLE") return "INPUT_INAPPLICABLE";
  if (availability === "INCOMPLETE") return "STUDENT_INPUT_INCOMPLETE";
  return "REQUIRED_INPUT_UNAVAILABLE";
}
