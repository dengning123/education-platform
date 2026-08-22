export type {
  KnowledgeStatusV02,
  TruthValueV02,
  ProjectionValue,
  EligibilityOutcomeV02,
  EligibilityProjection,
  GroupOperatorV02,
  RequirementStrengthV02,
  RequirementSemanticsV02,
  MappingStatusV02,
  UniverseRoleV02,
  ScopeKindV02,
  PredicateKindV02,
  LeafClass,
  MissingDataCodeV02,
} from "./generated.js";

export interface ProjectionThreshold {
  readonly groupNodeId: string;
  readonly projection: import("./generated.js").EligibilityProjection;
  readonly projectedMinimumChildren: number;
  readonly projectedDescendantCount: number;
}

export interface EvaluatedLeaf {
  readonly nodeId: string;
  readonly leafClass: import("./generated.js").LeafClass;
  readonly actual: import("./generated.js").TruthValueV02;
}

export interface EvaluatedGroup {
  readonly nodeId: string;
  readonly operator: import("./generated.js").GroupOperatorV02;
  readonly children: readonly EvaluatedNode[];
}

export type EvaluatedNode = EvaluatedLeaf | EvaluatedGroup;
