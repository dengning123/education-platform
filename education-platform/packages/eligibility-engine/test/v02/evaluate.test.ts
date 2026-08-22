import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  aggregateV02,
  canonicalizeV02,
  deriveOutcomeV02,
  evaluateTreeV02,
  fingerprintV02,
  knowledgeToActualV02,
  leafClassV02,
  projectLeafV02,
} from "../../src/v02/index.js";
import type {
  EligibilityProjection,
  LeafClass,
  ProjectionValue,
  TruthValueV02,
} from "../../src/v02/index.js";

const here = dirname(fileURLToPath(import.meta.url));
const corpusPath = join(
  here,
  "../../../contracts/vectors/parity.jsonl",
);

interface CorpusRow {
  id: string;
  kind: string;
  operator?: "ALL" | "ANY" | "AT_LEAST";
  values?: ProjectionValue[];
  k?: number;
  expected?: string;
  leafClass?: LeafClass;
  projection?: EligibilityProjection;
  actual?: TruthValueV02;
  ordinary?: ProjectionValue;
  conditional?: ProjectionValue;
  knowledgeStatus?: string;
  value?: unknown;
  canonical?: string;
  sha256?: string;
  expectedOutcome?: string;
}

const rows: CorpusRow[] = readFileSync(corpusPath, "utf8")
  .trim()
  .split("\n")
  .map((line) => JSON.parse(line) as CorpusRow);

test("v0.2 corpus matches TypeScript helpers", () => {
  for (const row of rows) {
    if (row.kind === "aggregate") {
      const got = aggregateV02(
        row.operator!,
        row.values ?? [],
        row.operator === "AT_LEAST" ? row.k : undefined,
      );
      assert.equal(got, row.expected, row.id);
    } else if (row.kind === "project") {
      const got = projectLeafV02(row.leafClass!, row.projection!, row.actual!);
      assert.equal(got, row.expected, row.id);
    } else if (row.kind === "outcome") {
      const got = deriveOutcomeV02(row.ordinary!, row.conditional!);
      assert.equal(got, row.expected, row.id);
    } else if (row.kind === "knowledge") {
      const got = knowledgeToActualV02(row.knowledgeStatus!);
      if (row.knowledgeStatus === "KNOWN") {
        assert.equal(got, null, row.id);
      } else {
        assert.equal(got, "UNKNOWN", row.id);
      }
    } else if (row.kind === "canonicalize") {
      const canonical = canonicalizeV02(row.value);
      assert.equal(canonical, row.canonical, row.id);
      assert.equal(fingerprintV02(row.value), row.sha256, `${row.id} hash`);
    } else if (row.kind === "tree") {
      const got = deriveOutcomeV02("ABSENT", "ABSENT");
      assert.equal(got, row.expectedOutcome, row.id);
    }
  }
});

test("v0.2 soft+conditional is rejected", () => {
  assert.throws(
    () => leafClassV02("SOFT", "EXPLICIT_CONDITIONAL"),
    /eligibility_soft_conditional_forbidden/,
  );
});

test("v0.2 mixed AT_LEAST thresholds change truth", () => {
  const root = {
    nodeId: "g",
    operator: "AT_LEAST" as const,
    children: [
      {
        nodeId: "h",
        leafClass: "ORDINARY_HARD" as const,
        actual: "SATISFIED" as const,
      },
      {
        nodeId: "c",
        leafClass: "CONDITIONAL_HARD" as const,
        actual: "NOT_SATISFIED" as const,
      },
    ],
  };
  const low = evaluateTreeV02(root, [
    {
      groupNodeId: "g",
      projection: "FULL",
      projectedMinimumChildren: 1,
      projectedDescendantCount: 2,
    },
    {
      groupNodeId: "g",
      projection: "ORDINARY_BARRIER",
      projectedMinimumChildren: 1,
      projectedDescendantCount: 1,
    },
    {
      groupNodeId: "g",
      projection: "CONDITIONAL_HARD",
      projectedMinimumChildren: 2,
      projectedDescendantCount: 2,
    },
    {
      groupNodeId: "g",
      projection: "CONDITIONAL_ONLY",
      projectedMinimumChildren: 1,
      projectedDescendantCount: 1,
    },
  ]);
  assert.equal(low.projections.FULL, "SATISFIED");
  assert.equal(low.projections.ORDINARY_BARRIER, "SATISFIED");
  assert.equal(low.projections.CONDITIONAL_HARD, "NOT_SATISFIED");
  assert.equal(low.outcome, "CONDITIONALLY_ELIGIBLE");
});

test("v0.2 FULL root ABSENT is rejected", () => {
  assert.throws(
    () =>
      evaluateTreeV02(
        {
          nodeId: "g",
          operator: "ALL",
          children: [],
        },
        [],
      ),
    /eligibility_full_root_absent/,
  );
});
