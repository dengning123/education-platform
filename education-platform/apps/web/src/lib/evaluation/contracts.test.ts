import { describe, expect, it } from "vitest";

import {
  FIT_DIMENSIONS,
  parseEligibilityConnectionRequest,
  parseFitConnectionRequest,
  projectFitEdgeResult,
  projectEligibilityAssemblyResult,
} from "./contracts";

const id = (suffix: string) => `00000000-0000-4000-8000-${suffix.padStart(12, "0")}`;

function fitRequest() {
  return {
    profileVersionId: id("1"), intentSetId: id("2"), programVersionId: id("3"), taxonomyReleaseCode: "v0.1",
    supersedesEvaluationId: null, eligibilityContextEvaluationId: null,
    evidence: {
      canonicalObservationIds: [], catalogMappingIds: [], studentCourseIds: [], studentMappingIds: [],
      taxonomyConceptIds: [], contextClaimIds: [], contextMappingIds: [], accessContextId: null,
      directFinancialComparisons: [], approvedFinancialNormalizationIds: [],
    },
  };
}

function fitEdgeResponse() {
  const dimensions = Object.fromEntries(FIT_DIMENSIONS.map((dimension) => [dimension, {
    dimension,
    methodRegistryId: id("10"),
    methodCode: `${dimension}_V01`,
    methodVersion: 1,
    assessment: "UNKNOWN",
    confidence: "LOW",
    evidenceCoverage: "INSUFFICIENT",
    inferenceCategory: "DETERMINISTIC",
    signals: [],
    reasons: [{
      methodRegistryId: id("10"), reasonDefinitionRegistryId: id("11"), reasonCode: "EVIDENCE_INSUFFICIENT",
      direction: "LIMITING", signalCode: null, signalTypeRegistryId: null, inputPolicyKey: null,
      inputPolicyRegistryId: null, mappingRelationRegistryId: null, exactManifestRefs: [],
    }],
    limitingInputs: [{
      methodRegistryId: id("10"), reasonCode: "EVIDENCE_INSUFFICIENT", reasonDefinitionRegistryId: id("11"),
      inputPolicyKey: "POLICY", inputPolicyRegistryId: id("12"), availability: "NOT_SUPPLIED",
      completenessManifestRef: null, provenanceManifestRef: null,
    }],
    exactManifestRefs: [],
  }]));
  return {
    evaluationId: id("4"), candidateInputFingerprint: "a".repeat(64), resultFingerprint: "b".repeat(64),
    schemaVersion: "fit-v0.1", dimensions,
  };
}

describe("closed evaluation contracts", () => {
  it("accepts only the three exact Eligibility assembly identities", () => {
    expect(parseEligibilityConnectionRequest({ profileVersionId: id("1"), programVersionId: id("2"), operationId: id("3") })).toEqual({
      profileVersionId: id("1"), programVersionId: id("2"), operationId: id("3"),
    });
    expect(() => parseEligibilityConnectionRequest({ profileVersionId: id("1"), programVersionId: id("2"), operationId: id("3"), studentId: id("4") })).toThrow(/exact closed contract/);
    expect(() => parseEligibilityConnectionRequest({ profileVersionId: id("1"), programVersionId: id("2"), operationId: id("3"), evaluatorBuild: "caller" })).toThrow();
    expect(parseEligibilityConnectionRequest({
      profileVersionId: id("1"), programVersionId: "00000000-0000-0000-0000-000000000401", operationId: id("3"),
    }).programVersionId).toBe("00000000-0000-0000-0000-000000000401");
  });

  it("keeps the Fit proxy request in exact parity with the existing Edge request", () => {
    expect(parseFitConnectionRequest(fitRequest())).toEqual(fitRequest());
    expect(() => parseFitConnectionRequest({ ...fitRequest(), studentId: id("8") })).toThrow(/exact closed contract/);
    expect(() => parseFitConnectionRequest({ ...fitRequest(), evidence: { ...fitRequest().evidence, arbitrary: [] } })).toThrow();
  });

  it("accepts only the database-authored closed Eligibility projection", () => {
    const result = projectEligibilityAssemblyResult({
      schemaVersion: "ELIGIBILITY_PRODUCTION_ASSEMBLY_V026",
      evalId: id("1"), profileId: id("2"), programId: id("4"),
      status: "NOT_ELIGIBLE", rootTruth: "NOT_SATISFIED",
      inputFingerprint: "a".repeat(64), resultFingerprint: "b".repeat(64),
      requirements: [{
        id: id("3"), truth: "NOT_SATISFIED", reasonCodes: ["REQUIREMENT_NOT_SATISFIED"],
        explanation: "The frozen test history does not contain this assessment.",
        missingDataCodes: [], supportingReferenceCount: 1,
      }],
    });
    expect(result).toEqual(expect.objectContaining({
      schemaVersion: "ELIGIBILITY_PRODUCTION_ASSEMBLY_V026", status: "NOT_ELIGIBLE",
    }));
    expect(result).not.toHaveProperty("supporting_fact_refs");
    expect(result.requirements[0]).toEqual({
      id: id("3"), truth: "NOT_SATISFIED", reasonCodes: ["REQUIREMENT_NOT_SATISFIED"],
      explanation: "The frozen test history does not contain this assessment.", missingDataCodes: [], supportingReferenceCount: 1,
    });
    expect(() => projectEligibilityAssemblyResult({ ...result, reviewerControl: "hidden" })).toThrow(/exact closed contract/);
  });

  it("projects a closed six-dimension Fit summary and rejects unknown nested fields", () => {
    const raw = fitEdgeResponse();
    const result = projectFitEdgeResult(raw);
    expect(Object.keys(result.dimensions)).toEqual(FIT_DIMENSIONS);
    expect(result.dimensions.ACADEMIC.reasonCodes).toEqual(["EVIDENCE_INSUFFICIENT"]);
    expect(result.dimensions.ACADEMIC.limitingInputCodes).toEqual(["EVIDENCE_INSUFFICIENT"]);
    expect(JSON.stringify(result)).not.toContain("exactManifestRefs");
    const tampered = structuredClone(raw);
    (tampered.dimensions.ACADEMIC as Record<string, unknown>).rawInternal = "leak";
    expect(() => projectFitEdgeResult(tampered)).toThrow(/exact closed contract/);
  });
});
