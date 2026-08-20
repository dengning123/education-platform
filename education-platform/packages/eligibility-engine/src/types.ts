export type TruthValue = "SATISFIED" | "NOT_SATISFIED" | "UNKNOWN";

export type EligibilityOutcome =
  | "ELIGIBLE"
  | "NOT_ELIGIBLE"
  | "UNKNOWN"
  | "CONDITIONALLY_ELIGIBLE";

export type Completeness = "COMPLETE" | "PARTIAL" | "UNKNOWN";
export type RequirementStrength = "HARD" | "SOFT";
export type RequirementSemantics = "ORDINARY" | "EXPLICIT_CONDITIONAL";
export type MappingStatus = "PROPOSED" | "VERIFIED" | "REJECTED" | "RETIRED";

export type KnowledgeStatus =
  | "KNOWN"
  | "NOT_YET_VERIFIED"
  | "NOT_PUBLICLY_DISCLOSED"
  | "NOT_APPLICABLE"
  | "SOURCE_CONFLICT"
  | "STALE";

export interface ProgramFactReference {
  readonly knowledgeStatus: KnowledgeStatus;
  readonly fieldObservationIds: readonly string[];
  readonly evidenceIds: readonly string[];
}

export interface GroupRuleNode {
  readonly id: string;
  readonly kind: "GROUP";
  readonly operator: "ALL" | "ANY" | "AT_LEAST";
  readonly minimumChildren?: number;
  readonly children: readonly RuleNode[];
  readonly explanationTemplate: string;
}

export interface PredicateRuleNode {
  readonly id: string;
  readonly kind: "PREDICATE";
  readonly predicateKind: "HAS_COURSE_CONCEPT" | "HAS_TEST";
  readonly requirementStrength: RequirementStrength;
  readonly requirementSemantics: RequirementSemantics;
  readonly targetConceptKey: string;
  readonly programFact: ProgramFactReference;
  readonly catalogMappingIds: readonly string[];
  readonly explanationTemplate: string;
}

export type RuleNode = GroupRuleNode | PredicateRuleNode;

export interface RuleSetInput {
  readonly ruleSetId: string;
  readonly programVersionId: string;
  readonly taxonomyReleaseCode: string;
  readonly ruleSchemaVersion: "phase2-v0.1";
  readonly engineContractVersion: "eligibility-v0.1";
  readonly root: RuleNode;
}

export interface StudentCourseFact {
  readonly id: string;
  readonly educationContextId: string | null;
  readonly status: "PLANNED" | "IN_PROGRESS" | "COMPLETED" | "WITHDRAWN";
  readonly evidenceIds: readonly string[];
}

export interface StudentTestFact {
  readonly id: string;
  readonly assessmentConceptKey: string;
  readonly evidenceIds: readonly string[];
}

export interface StudentMapping {
  readonly id: string;
  readonly recordType: "COURSE";
  readonly recordId: string;
  readonly conceptKey: string;
  readonly status: MappingStatus;
  readonly method: "HUMAN" | "RULE" | "MODEL";
  readonly confidence?: number;
  readonly reviewer?: string;
  readonly evidenceIds: readonly string[];
}

export interface StudentInput {
  readonly profileVersionId: string;
  readonly snapshotHash: string;
  readonly educationContextIds: readonly string[];
  readonly completeness: readonly StudentDataCompleteness[];
  readonly courses: readonly StudentCourseFact[];
  readonly tests: readonly StudentTestFact[];
  readonly mappings: readonly StudentMapping[];
}

export interface StudentDataCompleteness {
  readonly id: string;
  readonly educationContextId: string | null;
  readonly domain:
    | "EDUCATION_HISTORY"
    | "COURSE_HISTORY"
    | "COURSE_MAPPING"
    | "TEST_HISTORY"
    | "EXPERIENCE_HISTORY"
    | "SKILL_HISTORY"
    | "PREFERENCES"
    | "GOALS";
  readonly completeness: Completeness;
}

export interface EvaluationManifest {
  readonly inputFingerprint: string;
  readonly degreeIds: readonly string[];
  readonly courseIds: readonly string[];
  readonly testScoreIds: readonly string[];
  readonly studentMappingIds: readonly string[];
  readonly completenessRecordIds: readonly string[];
  readonly studentEvidenceIds: readonly string[];
  readonly catalogSourceObservationIds: readonly string[];
  readonly catalogMappingIds: readonly string[];
  readonly taxonomyConceptIds: readonly string[];
}

export interface EligibilityInput {
  readonly inputSchemaVersion: "eligibility-v0.1";
  readonly evaluatorVersion: string;
  readonly manifest: EvaluationManifest;
  readonly ruleSet: RuleSetInput;
  readonly student: StudentInput;
}

export interface MissingData {
  readonly domain: "PROGRAM_FACT" | "COURSEWORK" | "TESTS" | "COURSE_MAPPING";
  readonly code: string;
  readonly detail: string;
}

export interface NodeResult {
  readonly ruleNodeId: string;
  readonly truthValue: TruthValue;
  readonly reasonCodes: readonly string[];
  readonly explanation: string;
  readonly supportingFactRefs: readonly string[];
  readonly evidenceRefs: readonly string[];
  readonly missingData: readonly MissingData[];
  readonly decisive: boolean;
  readonly requirementStrength?: RequirementStrength;
  readonly requirementSemantics?: RequirementSemantics;
}

export interface EligibilityResult {
  readonly outcome: EligibilityOutcome;
  readonly rootTruthValue: TruthValue;
  readonly inputFingerprint: string;
  readonly ruleSetId: string;
  readonly profileVersionId: string;
  readonly nodeResults: readonly NodeResult[];
  readonly gaps: readonly MissingData[];
}
