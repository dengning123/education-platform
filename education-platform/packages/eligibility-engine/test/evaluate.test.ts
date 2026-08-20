import assert from "node:assert/strict";
import test from "node:test";
import {
  aggregateTruth,
  evaluateEligibility,
  type EligibilityInput,
  type PredicateRuleNode,
  type RuleNode,
  type TruthValue,
} from "../src/index.js";

const hash = "a".repeat(64);

function predicate(
  overrides: Partial<PredicateRuleNode> = {},
): PredicateRuleNode {
  return {
    id: "course-leaf",
    kind: "PREDICATE",
    predicateKind: "HAS_COURSE_CONCEPT",
    requirementStrength: "HARD",
    requirementSemantics: "ORDINARY",
    targetConceptKey: "COURSE_CONCEPT.CALCULUS_II",
    programFact: {
      knowledgeStatus: "KNOWN",
      fieldObservationIds: ["program-observation"],
      evidenceIds: ["program-evidence"],
    },
    catalogMappingIds: ["catalog-mapping"],
    explanationTemplate: "Calculus II is required.",
    ...overrides,
  };
}

function input(root: RuleNode, overrides: Partial<EligibilityInput["student"]> = {}): EligibilityInput {
  return {
    inputSchemaVersion: "eligibility-v0.1",
    evaluatorVersion: "0.1.0",
    manifest: {
      inputFingerprint: hash,
      degreeIds: [],
      courseIds: [],
      testScoreIds: [],
      studentMappingIds: [],
      completenessRecordIds: [],
      studentEvidenceIds: [],
      catalogSourceObservationIds: ["program-observation"],
      catalogMappingIds: ["catalog-mapping"],
      taxonomyConceptIds: [],
    },
    ruleSet: {
      ruleSetId: "rule-set",
      programVersionId: "program-version",
      taxonomyReleaseCode: "v0.1",
      ruleSchemaVersion: "phase2-v0.1",
      engineContractVersion: "eligibility-v0.1",
      root,
    },
    student: {
      profileVersionId: "profile",
      snapshotHash: hash,
      educationContextIds: [],
      completeness: [],
      courses: [],
      tests: [],
      mappings: [],
      ...overrides,
    },
  };
}

function courseCoverage(
  completeness: "COMPLETE" | "PARTIAL" | "UNKNOWN",
  educationContextId: string | null = null,
) {
  return [
    {
      id: `course-history-${educationContextId ?? "global"}`,
      educationContextId,
      domain: "COURSE_HISTORY" as const,
      completeness,
    },
    {
      id: `course-mapping-${educationContextId ?? "global"}`,
      educationContextId,
      domain: "COURSE_MAPPING" as const,
      completeness,
    },
  ] as const;
}

function deepFreeze<T>(value: T): T {
  if (value && typeof value === "object") {
    Object.freeze(value);
    for (const child of Object.values(value)) deepFreeze(child);
  }
  return value;
}

test("formal ANY, ALL, and AT_LEAST truth tables", () => {
  const states: readonly TruthValue[] = [
    "SATISFIED",
    "NOT_SATISFIED",
    "UNKNOWN",
  ];
  const combinations = (length: number): readonly TruthValue[][] => {
    if (length === 0) return [[]];
    return combinations(length - 1).flatMap((prefix) =>
      states.map((state) => [...prefix, state]),
    );
  };

  for (let childCount = 1; childCount <= 4; childCount += 1) {
    for (const values of combinations(childCount)) {
      const anyExpected: TruthValue = values.includes("SATISFIED")
        ? "SATISFIED"
        : values.includes("UNKNOWN")
          ? "UNKNOWN"
          : "NOT_SATISFIED";
      const allExpected: TruthValue = values.includes("NOT_SATISFIED")
        ? "NOT_SATISFIED"
        : values.includes("UNKNOWN")
          ? "UNKNOWN"
          : "SATISFIED";
      assert.equal(aggregateTruth("ANY", values), anyExpected, `ANY ${values}`);
      assert.equal(aggregateTruth("ALL", values), allExpected, `ALL ${values}`);

      for (let minimum = 1; minimum <= childCount; minimum += 1) {
        const satisfied = values.filter(
          (value) => value === "SATISFIED",
        ).length;
        const unknown = values.filter((value) => value === "UNKNOWN").length;
        const atLeastExpected: TruthValue =
          satisfied >= minimum
            ? "SATISFIED"
            : satisfied + unknown < minimum
              ? "NOT_SATISFIED"
              : "UNKNOWN";
        assert.equal(
          aggregateTruth("AT_LEAST", values, minimum),
          atLeastExpected,
          `AT_LEAST(${minimum}) ${values}`,
        );
      }
    }
  }
});

test("nested propagation preserves alternative and conjunctive uncertainty", () => {
  const failed = predicate({ id: "failed-calculus" });
  const unknown = predicate({
    id: "unknown-advanced-calculus",
    targetConceptKey: "COURSE_CONCEPT.ADVANCED_CALCULUS",
    programFact: {
      knowledgeStatus: "NOT_YET_VERIFIED",
      fieldObservationIds: ["unknown-program-observation"],
      evidenceIds: [],
    },
  });
  const anyResult = evaluateEligibility(
    input(
      {
        id: "alternative-root",
        kind: "GROUP",
        operator: "ANY",
        children: [failed, unknown],
        explanationTemplate: "Either calculus alternative is accepted.",
      },
      { completeness: courseCoverage("COMPLETE") },
    ),
  );
  assert.equal(anyResult.rootTruthValue, "UNKNOWN");
  assert.equal(anyResult.outcome, "UNKNOWN");

  const allResult = evaluateEligibility(
    input(
      {
        id: "conjunctive-root",
        kind: "GROUP",
        operator: "ALL",
        children: [failed, unknown],
        explanationTemplate: "Both preparation requirements apply.",
      },
      { completeness: courseCoverage("COMPLETE") },
    ),
  );
  assert.equal(allResult.rootTruthValue, "NOT_SATISFIED");
  assert.equal(allResult.outcome, "NOT_ELIGIBLE");
});

test("absence is failure only with complete course and mapping coverage", () => {
  const root = predicate();
  const unknown = evaluateEligibility(
    input(root, {
      completeness: courseCoverage("PARTIAL"),
    }),
  );
  assert.equal(unknown.outcome, "UNKNOWN");
  assert.equal(unknown.nodeResults[0]?.truthValue, "UNKNOWN");

  const confirmed = evaluateEligibility(
    input(root, {
      completeness: courseCoverage("COMPLETE"),
    }),
  );
  assert.equal(confirmed.outcome, "NOT_ELIGIBLE");
  assert.equal(confirmed.nodeResults[0]?.truthValue, "NOT_SATISFIED");
});

test("completeness is scoped to every declared education context", () => {
  const root = predicate();
  const result = evaluateEligibility(
    input(root, {
      educationContextIds: ["unc", "exchange"],
      completeness: [
        ...courseCoverage("UNKNOWN", "unc"),
        ...courseCoverage("COMPLETE", "exchange"),
      ],
    }),
  );
  assert.equal(result.outcome, "UNKNOWN");
  assert.equal(result.nodeResults[0]?.truthValue, "UNKNOWN");

  const allComplete = evaluateEligibility(
    input(root, {
      educationContextIds: ["unc", "exchange"],
      completeness: [
        ...courseCoverage("COMPLETE", "unc"),
        ...courseCoverage("COMPLETE", "exchange"),
      ],
    }),
  );
  assert.equal(allComplete.outcome, "NOT_ELIGIBLE");

  const mismatchedCourseContext = evaluateEligibility(
    input(root, {
      educationContextIds: ["unc"],
      completeness: courseCoverage("COMPLETE", "unc"),
      courses: [
        {
          id: "exchange-course",
          educationContextId: "exchange",
          status: "COMPLETED",
          evidenceIds: ["exchange-transcript"],
        },
      ],
      mappings: [
        {
          id: "exchange-mapping",
          recordType: "COURSE",
          recordId: "exchange-course",
          conceptKey: "COURSE_CONCEPT.CALCULUS_II",
          status: "VERIFIED",
          method: "HUMAN",
          reviewer: "reviewer",
          evidenceIds: ["mapping-evidence"],
        },
      ],
    }),
  );
  assert.equal(mismatchedCourseContext.outcome, "UNKNOWN");
  assert.equal(
    mismatchedCourseContext.nodeResults[0]?.missingData[0]?.code,
    "COURSE_EDUCATION_CONTEXT_MISMATCH",
  );
});

test("only VERIFIED mappings satisfy; confidence is ignored", () => {
  const root = predicate();
  const baseStudent: Partial<EligibilityInput["student"]> = {
    completeness: courseCoverage("COMPLETE"),
    courses: [
      {
        id: "course",
        educationContextId: null,
        status: "COMPLETED",
        evidenceIds: ["transcript"],
      },
    ],
  };
  const proposed = evaluateEligibility(
    input(root, {
      ...baseStudent,
      mappings: [
        {
          id: "mapping",
          recordType: "COURSE",
          recordId: "course",
          conceptKey: "COURSE_CONCEPT.CALCULUS_II",
          status: "PROPOSED",
          method: "MODEL",
          confidence: 1,
          evidenceIds: [],
        },
      ],
    }),
  );
  assert.equal(proposed.outcome, "UNKNOWN");

  const verified = evaluateEligibility(
    input(root, {
      ...baseStudent,
      mappings: [
        {
          id: "mapping",
          recordType: "COURSE",
          recordId: "course",
          conceptKey: "COURSE_CONCEPT.CALCULUS_II",
          status: "VERIFIED",
          method: "MODEL",
          confidence: 0,
          reviewer: "reviewer",
          evidenceIds: ["mapping-evidence"],
        },
      ],
    }),
  );
  assert.equal(verified.outcome, "ELIGIBLE");
});

test("non-known program facts produce UNKNOWN before student absence", () => {
  const result = evaluateEligibility(
    input(
      predicate({
        programFact: {
          knowledgeStatus: "SOURCE_CONFLICT",
          fieldObservationIds: ["conflicted-observation"],
          evidenceIds: ["source-a", "source-b"],
        },
      }),
      {
        completeness: courseCoverage("COMPLETE"),
      },
    ),
  );
  assert.equal(result.outcome, "UNKNOWN");
  assert.deepEqual(result.nodeResults[0]?.reasonCodes, ["PROGRAM_FACT_UNKNOWN"]);
});

test("soft gaps do not downgrade and known conditional gaps are conditional", () => {
  const soft = evaluateEligibility(
    input(
      predicate({
        requirementStrength: "SOFT",
      }),
      {
        completeness: courseCoverage("COMPLETE"),
      },
    ),
  );
  assert.equal(soft.outcome, "ELIGIBLE");

  const conditional = evaluateEligibility(
    input(
      predicate({
        requirementSemantics: "EXPLICIT_CONDITIONAL",
      }),
      {
        completeness: courseCoverage("COMPLETE"),
      },
    ),
  );
  assert.equal(conditional.outcome, "CONDITIONALLY_ELIGIBLE");

  const unknownConditional = evaluateEligibility(
    input(
      predicate({
        requirementSemantics: "EXPLICIT_CONDITIONAL",
      }),
      {
        completeness: courseCoverage("UNKNOWN"),
      },
    ),
  );
  assert.equal(unknownConditional.outcome, "UNKNOWN");
});

test("evaluation is deterministic, side-effect-free, and deeply explainable", () => {
  const frozenInput = deepFreeze(
    input(predicate(), {
      completeness: courseCoverage("COMPLETE"),
      courses: [
        {
          id: "course",
          educationContextId: null,
          status: "COMPLETED",
          evidenceIds: ["transcript"],
        },
      ],
      mappings: [
        {
          id: "mapping",
          recordType: "COURSE",
          recordId: "course",
          conceptKey: "COURSE_CONCEPT.CALCULUS_II",
          status: "VERIFIED",
          method: "HUMAN",
          reviewer: "reviewer",
          evidenceIds: ["mapping-evidence"],
        },
      ],
    }),
  );
  const first = evaluateEligibility(frozenInput);
  const second = evaluateEligibility(frozenInput);
  assert.deepEqual(first, second);
  assert.deepEqual(first, {
    outcome: "ELIGIBLE",
    rootTruthValue: "SATISFIED",
    inputFingerprint: hash,
    ruleSetId: "rule-set",
    profileVersionId: "profile",
    nodeResults: [
      {
        ruleNodeId: "course-leaf",
        truthValue: "SATISFIED",
        reasonCodes: ["VERIFIED_COURSE_MATCH"],
        explanation: "Calculus II is required.",
        supportingFactRefs: [
          "program-observation",
          "catalog-mapping",
          "course",
          "mapping",
        ],
        evidenceRefs: [
          "program-evidence",
          "transcript",
          "mapping-evidence",
        ],
        missingData: [],
        decisive: false,
        requirementStrength: "HARD",
        requirementSemantics: "ORDINARY",
      },
    ],
    gaps: [],
  });
  assert.equal(
    JSON.stringify(first).includes("NOT_APPLICABLE"),
    false,
    "v0.1 never emits NOT_APPLICABLE",
  );
});
