import { describe, expect, it } from "vitest";

import {
  FIT_INTENT_DIMENSIONS,
  parseFitIntentCreateRequest,
  parseFitIntentDocument,
  parseFitIntentMutationRequest,
  parseFitIntentTaxonomyRequest,
} from "./contracts";

const id = (suffix: string) => `00000000-0000-4000-8000-${suffix.padStart(12, "0")}`;

function document() {
  return {
    schemaVersion: "FIT_INTENT_DOCUMENT_V027", intentSetId: id("1"), profileVersionId: id("2"),
    versionNumber: 1, status: "DRAFT", revision: 0, snapshotHash: null,
    taxonomyRelease: { releaseCode: "v0.1", releaseOrdinal: 1 },
    dimensions: FIT_INTENT_DIMENSIONS.map((dimension) => ({ dimension, state: "UNANSWERED" })),
    declarations: [], accessContext: null,
  };
}

describe("M027 browser intent contracts", () => {
  it("accepts only product identities and rejects caller authority", () => {
    expect(parseFitIntentCreateRequest({ profileVersionId: id("1"), operationId: id("2") })).toEqual({ profileVersionId: id("1"), operationId: id("2") });
    for (const forbidden of ["studentId", "authSubject", "reviewerId", "verified", "serviceRole"]) {
      expect(() => parseFitIntentCreateRequest({ profileVersionId: id("1"), operationId: id("2"), [forbidden]: id("9") })).toThrow();
    }
  });

  it("closes declaration commands and typed values", () => {
    const base = { intentSetId: id("1"), operationId: id("2"), expectedRevision: 0 };
    const parsed = parseFitIntentMutationRequest({
      ...base, command: "DECLARATION_CREATE", payload: { declaration: {
        dimension: "GEOGRAPHIC_DELIVERY", semanticType: "DELIVERY_CONSTRAINT", importance: "REQUIRED",
        importanceConfirmedByStudent: true, typedValue: { deliveryMode: "ONLINE", relation: "DESIRED" },
      } },
    });
    expect(parsed.command).toBe("DECLARATION_CREATE");
    expect(() => parseFitIntentMutationRequest({ ...parsed, payload: { ...parsed.payload, arbitrary: "value" } })).toThrow();
    expect(() => parseFitIntentMutationRequest({
      ...base, command: "DECLARATION_CREATE", payload: { declaration: {
        dimension: "ACADEMIC", semanticType: "DELIVERY_CONSTRAINT", importance: "PREFERRED",
        importanceConfirmedByStudent: true, typedValue: { deliveryMode: "ONLINE", relation: "DESIRED" },
      } },
    })).toThrow();
  });

  it("requires explicit confirmation for REQUIRED and forbids arbitrary financial semantics", () => {
    const base = { intentSetId: id("1"), operationId: id("2"), expectedRevision: 0, command: "DECLARATION_CREATE" };
    expect(() => parseFitIntentMutationRequest({ ...base, payload: { declaration: {
      dimension: "PERSONAL_PREFERENCE", semanticType: "PROGRAM_FEATURE_CONSTRAINT", importance: "REQUIRED",
      importanceConfirmedByStudent: false, typedValue: { featureKey: "CAPSTONE_AVAILABLE", expected: true },
    } } })).toThrow();
    expect(() => parseFitIntentMutationRequest({ ...base, payload: { declaration: {
      dimension: "FINANCIAL", semanticType: "FINANCIAL_CONSTRAINT", importance: "PREFERRED",
      importanceConfirmedByStudent: true,
      typedValue: { amount: 10, constraintSemantics: "CHEAP", currency: "USD", scope: "TOTAL_COST", period: "PROGRAM_DURATION", basis: "GROSS", components: ["TOTAL_COST"] },
    } } })).toThrow();
  });

  it("projects readiness without inventing neutral intent", () => {
    const result = parseFitIntentDocument(document());
    expect(result.readiness.freezeReady).toBe(false);
    expect(result.readiness.issues).toHaveLength(6);
    const complete = structuredClone(document());
    complete.dimensions = FIT_INTENT_DIMENSIONS.map((dimension) => ({ dimension, state: "EXPLICIT_NOT_SUPPLIED" }));
    expect(parseFitIntentDocument(complete).readiness).toEqual({ freezeReady: true, issues: [] });
  });

  it("fails closed on forged provenance, duplicate dimensions, and invalid taxonomy dimensions", () => {
    const forged = { ...document(), declarations: [{
      declarationId: id("3"), dimension: "GEOGRAPHIC_DELIVERY", semanticType: "DELIVERY_CONSTRAINT",
      importance: "PREFERRED", importanceConfirmedByStudent: true, provenance: "VERIFIED",
      typedValue: { deliveryMode: "ONLINE", relation: "DESIRED" },
    }] };
    expect(() => parseFitIntentDocument(forged)).toThrow();
    const duplicate = structuredClone(document());
    duplicate.dimensions[1].dimension = duplicate.dimensions[0].dimension;
    expect(() => parseFitIntentDocument(duplicate)).toThrow();
    expect(() => parseFitIntentTaxonomyRequest({ intentSetId: id("1"), dimension: "FINANCIAL" })).toThrow();
  });
});
