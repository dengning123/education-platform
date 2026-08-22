import type {
  EligibilityOutcomeV02,
  EligibilityProjection,
  GroupOperatorV02,
  LeafClass,
  ProjectionValue,
  RequirementSemanticsV02,
  RequirementStrengthV02,
  TruthValueV02,
} from "./generated.js";
import type { EvaluatedGroup, EvaluatedNode, ProjectionThreshold } from "./types.js";

export function leafClassV02(
  strength: RequirementStrengthV02,
  semantics: RequirementSemanticsV02,
): LeafClass {
  if (strength === "SOFT" && semantics === "EXPLICIT_CONDITIONAL") {
    throw new Error("eligibility_soft_conditional_forbidden");
  }
  if (strength === "HARD" && semantics === "ORDINARY") return "ORDINARY_HARD";
  if (strength === "HARD" && semantics === "EXPLICIT_CONDITIONAL") {
    return "CONDITIONAL_HARD";
  }
  return "SOFT";
}

export function projectLeafV02(
  leafClass: LeafClass,
  projection: EligibilityProjection,
  actual: TruthValueV02,
): ProjectionValue {
  switch (leafClass) {
    case "ORDINARY_HARD":
      return projection === "CONDITIONAL_ONLY" || projection === "SOFT_EXPLANATION"
        ? "ABSENT"
        : actual;
    case "CONDITIONAL_HARD":
      if (projection === "ORDINARY_BARRIER") return "SATISFIED";
      if (projection === "SOFT_EXPLANATION") return "ABSENT";
      return actual;
    case "SOFT":
      return projection === "FULL" || projection === "SOFT_EXPLANATION"
        ? actual
        : "ABSENT";
    default: {
      const exhaustive: never = leafClass;
      throw new Error(`unknown leaf class ${exhaustive}`);
    }
  }
}

export function aggregateV02(
  operator: GroupOperatorV02,
  values: readonly ProjectionValue[],
  projectedMinimumChildren?: number,
): ProjectionValue {
  const remaining = values.filter((value) => value !== "ABSENT");
  if (remaining.length === 0) return "ABSENT";
  const satisfied = remaining.filter((value) => value === "SATISFIED").length;
  const unknown = remaining.filter((value) => value === "UNKNOWN").length;

  if (operator === "ALL") {
    if (remaining.includes("NOT_SATISFIED")) return "NOT_SATISFIED";
    if (unknown > 0) return "UNKNOWN";
    return "SATISFIED";
  }
  if (operator === "ANY") {
    if (satisfied > 0) return "SATISFIED";
    if (unknown > 0) return "UNKNOWN";
    return "NOT_SATISFIED";
  }
  if (projectedMinimumChildren === undefined) {
    throw new Error("eligibility_missing_projected_threshold");
  }
  if (satisfied >= projectedMinimumChildren) return "SATISFIED";
  if (satisfied + unknown < projectedMinimumChildren) return "NOT_SATISFIED";
  return "UNKNOWN";
}

export function deriveOutcomeV02(
  ordinary: ProjectionValue,
  conditional: ProjectionValue,
): EligibilityOutcomeV02 | "INVALID_STATE" {
  if (ordinary !== "ABSENT" && conditional === "ABSENT") return "INVALID_STATE";
  if (ordinary === "NOT_SATISFIED") return "NOT_ELIGIBLE";
  if (ordinary === "UNKNOWN") return "UNKNOWN";
  if (ordinary === "SATISFIED" || ordinary === "ABSENT") {
    if (conditional === "SATISFIED" || conditional === "ABSENT") return "ELIGIBLE";
    if (conditional === "NOT_SATISFIED") return "CONDITIONALLY_ELIGIBLE";
    if (conditional === "UNKNOWN") return "UNKNOWN";
  }
  return "INVALID_STATE";
}

export function knowledgeToActualV02(
  knowledgeStatus: string,
): TruthValueV02 | null {
  if (knowledgeStatus === "KNOWN") return null;
  return "UNKNOWN";
}

function belongs(
  node: EvaluatedNode,
  projection: EligibilityProjection,
): boolean {
  if (!("operator" in node)) {
    return projectLeafV02(node.leafClass, projection, node.actual) !== "ABSENT";
  }
  return node.children.some((child) => belongs(child, projection));
}

function evaluateProjection(
  node: EvaluatedNode,
  projection: EligibilityProjection,
  thresholds: readonly ProjectionThreshold[],
): ProjectionValue {
  if (!("operator" in node)) {
    return projectLeafV02(node.leafClass, projection, node.actual);
  }
  const childValues = node.children.map((child) =>
    evaluateProjection(child, projection, thresholds),
  );
  const remaining = childValues.filter((value) => value !== "ABSENT");
  if (remaining.length === 0) return "ABSENT";
  let k: number | undefined;
  if (node.operator === "AT_LEAST") {
    const row = thresholds.find(
      (threshold) =>
        threshold.groupNodeId === node.nodeId &&
        threshold.projection === projection,
    );
    if (!row) throw new Error("eligibility_missing_projected_threshold");
    k = row.projectedMinimumChildren;
  }
  return aggregateV02(node.operator, childValues, k);
}

export interface TreeEvaluationV02 {
  readonly projections: Record<EligibilityProjection, ProjectionValue>;
  readonly outcome: EligibilityOutcomeV02;
}

export function evaluateTreeV02(
  root: EvaluatedNode,
  thresholds: readonly ProjectionThreshold[],
): TreeEvaluationV02 {
  const projections = {
    FULL: evaluateProjection(root, "FULL", thresholds),
    ORDINARY_BARRIER: evaluateProjection(root, "ORDINARY_BARRIER", thresholds),
    CONDITIONAL_HARD: evaluateProjection(root, "CONDITIONAL_HARD", thresholds),
    CONDITIONAL_ONLY: evaluateProjection(root, "CONDITIONAL_ONLY", thresholds),
    SOFT_EXPLANATION: evaluateProjection(root, "SOFT_EXPLANATION", thresholds),
  } as const;
  if (projections.FULL === "ABSENT") {
    throw new Error("eligibility_full_root_absent");
  }
  const outcome = deriveOutcomeV02(
    projections.ORDINARY_BARRIER,
    projections.CONDITIONAL_HARD,
  );
  if (outcome === "INVALID_STATE") {
    throw new Error("eligibility_projection_invalid_state");
  }
  return { projections, outcome };
}

export function nodeBelongsToProjection(
  node: EvaluatedNode,
  projection: EligibilityProjection,
): boolean {
  return belongs(node, projection);
}
