import { ReasonCode } from "./reasons.js";
import type {
  EligibilityInput,
  EligibilityOutcome,
  EligibilityResult,
  GroupRuleNode,
  MissingData,
  NodeResult,
  PredicateRuleNode,
  StudentInput,
  TruthValue,
} from "./types.js";

export function aggregateTruth(
  operator: GroupRuleNode["operator"],
  values: readonly TruthValue[],
  minimumChildren?: number,
): TruthValue {
  const satisfied = values.filter((value) => value === "SATISFIED").length;
  const unknown = values.filter((value) => value === "UNKNOWN").length;

  if (operator === "ANY") {
    if (satisfied > 0) return "SATISFIED";
    if (unknown > 0) return "UNKNOWN";
    return "NOT_SATISFIED";
  }

  if (operator === "ALL") {
    if (values.includes("NOT_SATISFIED")) return "NOT_SATISFIED";
    if (unknown > 0) return "UNKNOWN";
    return "SATISFIED";
  }

  if (
    minimumChildren === undefined ||
    minimumChildren <= 0 ||
    minimumChildren > values.length
  ) {
    return "UNKNOWN";
  }
  if (satisfied >= minimumChildren) return "SATISFIED";
  if (satisfied + unknown < minimumChildren) return "NOT_SATISFIED";
  return "UNKNOWN";
}

interface InternalEvaluation {
  readonly truthValue: TruthValue;
  readonly ordinaryHardTruth: TruthValue | null;
  readonly conditionalHardTruths: readonly TruthValue[];
  readonly results: readonly NodeResult[];
}

function unknownProgramFact(node: PredicateRuleNode): InternalEvaluation {
  const missing: MissingData = {
    domain: "PROGRAM_FACT",
    code: node.programFact.knowledgeStatus,
    detail: "The selected program fact is not currently known.",
  };
  return predicateResult(node, "UNKNOWN", [ReasonCode.PROGRAM_FACT_UNKNOWN], {
    missingData: [missing],
    evidenceRefs: node.programFact.evidenceIds,
    supportingFactRefs: node.programFact.fieldObservationIds,
  });
}

function predicateResult(
  node: PredicateRuleNode,
  truthValue: TruthValue,
  reasonCodes: readonly string[],
  details: {
    readonly missingData?: readonly MissingData[];
    readonly evidenceRefs?: readonly string[];
    readonly supportingFactRefs?: readonly string[];
  } = {},
): InternalEvaluation {
  const effectiveReasons =
    node.requirementStrength === "SOFT"
      ? [...reasonCodes, ReasonCode.SOFT_REQUIREMENT_NON_BLOCKING]
      : reasonCodes;
  const result: NodeResult = {
    ruleNodeId: node.id,
    truthValue,
    reasonCodes: effectiveReasons,
    explanation: node.explanationTemplate,
    supportingFactRefs: details.supportingFactRefs ?? [],
    evidenceRefs: details.evidenceRefs ?? [],
    missingData: details.missingData ?? [],
    decisive:
      node.requirementStrength === "HARD" &&
      node.requirementSemantics === "ORDINARY" &&
      truthValue !== "SATISFIED",
    requirementStrength: node.requirementStrength,
    requirementSemantics: node.requirementSemantics,
  };

  return {
    truthValue,
    ordinaryHardTruth:
      node.requirementStrength === "HARD" &&
      node.requirementSemantics === "ORDINARY"
        ? truthValue
        : null,
    conditionalHardTruths:
      node.requirementStrength === "HARD" &&
      node.requirementSemantics === "EXPLICIT_CONDITIONAL"
        ? [truthValue]
        : [],
    results: [result],
  };
}

function evaluateCourse(
  node: PredicateRuleNode,
  student: StudentInput,
): InternalEvaluation {
  const relevantMappings = student.mappings.filter(
    (mapping) =>
      mapping.recordType === "COURSE" &&
      mapping.conceptKey === node.targetConceptKey,
  );
  const verifiedMappings = relevantMappings.filter(
    (mapping) => mapping.status === "VERIFIED",
  );

  for (const mapping of verifiedMappings) {
    const course = student.courses.find(
      (candidate) => candidate.id === mapping.recordId,
    );
    const courseContextIsDeclared =
      course !== undefined &&
      (course.educationContextId === null
        ? student.educationContextIds.length === 0
        : student.educationContextIds.includes(course.educationContextId));
    if (course?.status === "COMPLETED" && courseContextIsDeclared) {
      return predicateResult(
        node,
        "SATISFIED",
        [ReasonCode.VERIFIED_COURSE_MATCH],
        {
          supportingFactRefs: [
            ...node.programFact.fieldObservationIds,
            ...node.catalogMappingIds,
            course.id,
            mapping.id,
          ],
          evidenceRefs: [
            ...node.programFact.evidenceIds,
            ...course.evidenceIds,
            ...mapping.evidenceIds,
          ],
        },
      );
    }
    if (!course) {
      return predicateResult(
        node,
        "UNKNOWN",
        [ReasonCode.COURSE_HISTORY_INCOMPLETE],
        {
          missingData: [
            {
              domain: "COURSEWORK",
              code: "MAPPED_COURSE_NOT_INCLUDED",
              detail: "A verified mapping references a course outside the manifest.",
            },
          ],
          supportingFactRefs: [mapping.id],
        },
      );
    }
    if (!courseContextIsDeclared) {
      return predicateResult(
        node,
        "UNKNOWN",
        [ReasonCode.COURSE_HISTORY_INCOMPLETE],
        {
          missingData: [
            {
              domain: "COURSEWORK",
              code: "COURSE_EDUCATION_CONTEXT_MISMATCH",
              detail:
                "The mapped course is not scoped to a declared education context.",
            },
          ],
          supportingFactRefs: [course.id, mapping.id],
        },
      );
    }
  }

  if (relevantMappings.some((mapping) => mapping.status !== "VERIFIED")) {
    return predicateResult(
      node,
      "UNKNOWN",
      [ReasonCode.COURSE_MAPPING_UNRESOLVED],
      {
        missingData: [
          {
            domain: "COURSE_MAPPING",
            code: "NO_VERIFIED_MAPPING",
            detail: "A possible equivalency exists but lacks normative verification.",
          },
        ],
        supportingFactRefs: relevantMappings.map((mapping) => mapping.id),
      },
    );
  }

  const educationContexts =
    student.educationContextIds.length > 0
      ? student.educationContextIds
      : [null];
  const completeAcrossEveryContext = educationContexts.every(
    (educationContextId) =>
      student.completeness.some(
        (entry) =>
          entry.educationContextId === educationContextId &&
          entry.domain === "COURSE_HISTORY" &&
          entry.completeness === "COMPLETE",
      ) &&
      student.completeness.some(
        (entry) =>
          entry.educationContextId === educationContextId &&
          entry.domain === "COURSE_MAPPING" &&
          entry.completeness === "COMPLETE",
      ),
  );

  if (completeAcrossEveryContext) {
    return predicateResult(
      node,
      "NOT_SATISFIED",
      [ReasonCode.REQUIRED_COURSE_ABSENT],
      {
        supportingFactRefs: node.programFact.fieldObservationIds,
        evidenceRefs: node.programFact.evidenceIds,
      },
    );
  }

  return predicateResult(
    node,
    "UNKNOWN",
    [ReasonCode.COURSE_HISTORY_INCOMPLETE],
    {
      missingData: [
        {
          domain: "COURSEWORK",
          code: "INCOMPLETE_COURSE_OR_MAPPING_COVERAGE",
          detail:
            "Course history and reviewed mapping coverage must both be complete for every education context to prove absence.",
        },
      ],
    },
  );
}

function evaluateTest(
  node: PredicateRuleNode,
  student: StudentInput,
): InternalEvaluation {
  const test = student.tests.find(
    (candidate) =>
      candidate.assessmentConceptKey === node.targetConceptKey,
  );
  if (test) {
    return predicateResult(
      node,
      "SATISFIED",
      [ReasonCode.VERIFIED_TEST_PRESENT],
      {
        supportingFactRefs: [
          ...node.programFact.fieldObservationIds,
          test.id,
        ],
        evidenceRefs: [...node.programFact.evidenceIds, ...test.evidenceIds],
      },
    );
  }
  if (
    student.completeness.some(
      (entry) =>
        entry.educationContextId === null &&
        entry.domain === "TEST_HISTORY" &&
        entry.completeness === "COMPLETE",
    )
  ) {
    return predicateResult(
      node,
      "NOT_SATISFIED",
      [ReasonCode.REQUIRED_TEST_ABSENT],
      {
        supportingFactRefs: node.programFact.fieldObservationIds,
        evidenceRefs: node.programFact.evidenceIds,
      },
    );
  }
  return predicateResult(
    node,
    "UNKNOWN",
    [ReasonCode.TEST_HISTORY_INCOMPLETE],
    {
      missingData: [
        {
          domain: "TESTS",
          code: "INCOMPLETE_TEST_HISTORY",
          detail: "The test history is not confirmed complete.",
        },
      ],
    },
  );
}

function evaluatePredicate(
  node: PredicateRuleNode,
  student: StudentInput,
): InternalEvaluation {
  if (node.programFact.knowledgeStatus !== "KNOWN") {
    return unknownProgramFact(node);
  }
  if (node.predicateKind === "HAS_COURSE_CONCEPT") {
    return evaluateCourse(node, student);
  }
  return evaluateTest(node, student);
}

function evaluateNode(
  node: EligibilityInput["ruleSet"]["root"],
  student: StudentInput,
): InternalEvaluation {
  if (node.kind === "PREDICATE") {
    return evaluatePredicate(node, student);
  }

  const children = node.children.map((child) => evaluateNode(child, student));
  const truthValue = aggregateTruth(
    node.operator,
    children.map((child) => child.truthValue),
    node.minimumChildren,
  );
  const ordinaryHardValues = children
    .map((child) => child.ordinaryHardTruth)
    .filter((value): value is TruthValue => value !== null);
  const ordinaryHardTruth =
    ordinaryHardValues.length === 0
      ? null
      : aggregateTruth(node.operator, ordinaryHardValues, node.minimumChildren);
  const reasonCode =
    truthValue === "SATISFIED"
      ? ReasonCode.GROUP_SATISFIED
      : truthValue === "NOT_SATISFIED"
        ? ReasonCode.GROUP_NOT_SATISFIED
        : ReasonCode.GROUP_UNKNOWN;
  const missingData = children.flatMap((child) =>
    child.results.flatMap((result) => result.missingData),
  );
  const groupResult: NodeResult = {
    ruleNodeId: node.id,
    truthValue,
    reasonCodes: [reasonCode],
    explanation: node.explanationTemplate,
    supportingFactRefs: [],
    evidenceRefs: [],
    missingData: truthValue === "UNKNOWN" ? missingData : [],
    decisive: false,
  };
  return {
    truthValue,
    ordinaryHardTruth,
    conditionalHardTruths: children.flatMap(
      (child) => child.conditionalHardTruths,
    ),
    results: [...children.flatMap((child) => child.results), groupResult],
  };
}

function overallOutcome(
  ordinaryHardTruth: TruthValue,
  conditionalTruths: readonly TruthValue[],
): EligibilityOutcome {
  if (ordinaryHardTruth === "NOT_SATISFIED") return "NOT_ELIGIBLE";
  if (ordinaryHardTruth === "UNKNOWN") return "UNKNOWN";
  if (conditionalTruths.includes("UNKNOWN")) return "UNKNOWN";
  if (conditionalTruths.includes("NOT_SATISFIED")) {
    return "CONDITIONALLY_ELIGIBLE";
  }
  return "ELIGIBLE";
}

export function evaluateEligibility(input: EligibilityInput): EligibilityResult {
  const evaluated = evaluateNode(input.ruleSet.root, input.student);
  const ordinaryHardTruth = evaluated.ordinaryHardTruth ?? "SATISFIED";
  const outcome = overallOutcome(
    ordinaryHardTruth,
    evaluated.conditionalHardTruths,
  );
  const gaps = evaluated.results.flatMap((result) => result.missingData);

  return {
    outcome,
    rootTruthValue: ordinaryHardTruth,
    inputFingerprint: input.manifest.inputFingerprint,
    ruleSetId: input.ruleSet.ruleSetId,
    profileVersionId: input.student.profileVersionId,
    nodeResults: evaluated.results,
    gaps,
  };
}
