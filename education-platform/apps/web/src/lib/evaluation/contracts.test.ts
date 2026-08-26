import { describe, expect, it } from "vitest";

import {
  FIT_DIMENSIONS,
  parseFitEvaluationAssembly,
  parseEligibilityConnectionRequest,
  parseFitConnectionRequest,
  projectFitEdgeResult,
  projectEligibilityAssemblyResult,
} from "./contracts";

const id = (suffix: string) => `00000000-0000-4000-8000-${suffix.padStart(12, "0")}`;

function fitRequest() {
  return {
    profileVersionId: id("1"), intentSetId: id("2"), programVersionId: id("3"),
    completedEligibilityEvaluationId: null, operationId: id("5"),
  };
}

function intentDocument() {
  return {
    schemaVersion: "FIT_INTENT_DOCUMENT_V027", intentSetId: id("2"), profileVersionId: id("1"),
    versionNumber: 1, status: "FROZEN", revision: 7, snapshotHash: "c".repeat(64),
    taxonomyRelease: { releaseCode: "v0.1", releaseOrdinal: 1 },
    dimensions: FIT_DIMENSIONS.map((dimension) => ({ dimension, state: "EXPLICIT_NOT_SUPPLIED" })),
    declarations: [], accessContext: null,
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

  it("accepts only the high-level product Fit identities", () => {
    expect(parseFitConnectionRequest(fitRequest())).toEqual(fitRequest());
    expect(() => parseFitConnectionRequest({ ...fitRequest(), studentId: id("8") })).toThrow(/exact closed contract/);
    for (const forbidden of ["taxonomyReleaseCode", "supersedesEvaluationId", "evidence", "accessContextId", "canonicalObservationIds"]) {
      expect(() => parseFitConnectionRequest({ ...fitRequest(), [forbidden]: forbidden === "evidence" ? {} : id("9") })).toThrow(/exact closed contract/);
    }
    expect(() => parseFitConnectionRequest({ ...fitRequest(), completedEligibilityEvaluationId: undefined })).toThrow();
    const withoutEligibility = {
      profileVersionId: id("1"), intentSetId: id("2"), programVersionId: id("3"), operationId: id("5"),
    };
    expect(parseFitConnectionRequest(withoutEligibility).completedEligibilityEvaluationId).toBeNull();
  });

  it("accepts only a frozen, identity-consistent M027 Fit assembly", () => {
    const raw = {
      schemaVersion: "FIT_EVALUATION_ASSEMBLY_V027", profileVersionId: id("1"), intentSetId: id("2"),
      programVersionId: id("3"), intentSnapshotHash: "c".repeat(64), intentDocument: intentDocument(),
      dimensions: FIT_DIMENSIONS.map((dimension) => ({
        dimension, disposition: "EXPLICIT_NOT_SUPPLIED", inputAvailability: "NOT_SUPPLIED",
        completenessDomain: ["ACADEMIC", "CAREER", "INTERNATIONAL_ACCESSIBILITY"].includes(dimension) ? "GOALS" : "PREFERENCES",
        completenessId: id(String(100 + FIT_DIMENSIONS.indexOf(dimension))), profileCompleteness: "UNKNOWN",
      })),
    };
    expect(parseFitEvaluationAssembly(raw).intentSetId).toBe(id("2"));
    expect(() => parseFitEvaluationAssembly({ ...raw, intentSnapshotHash: "d".repeat(64) })).toThrow(/identity is inconsistent/);
    const aliased = structuredClone(raw);
    aliased.dimensions[1].dimension = aliased.dimensions[0].dimension;
    expect(() => parseFitEvaluationAssembly(aliased)).toThrow(/unique/);
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
