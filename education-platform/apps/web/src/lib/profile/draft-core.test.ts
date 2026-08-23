import { describe, expect, it } from "vitest";

import type { ProfileDocument } from "./contracts";
import {
  completenessDescription,
  completenessScopes,
  courseUpdatePayload,
  degreeUpdatePayload,
  evidenceUpdatePayload,
  mappingLabelsFor,
  profileOverview,
  sourceDescription,
  type ProfileCourse,
  type ProfileDegree,
  type ProfileEvidenceItem,
} from "./draft-core";

const id = (suffix: string) => `00000000-0000-4000-8000-${suffix.padStart(12, "0")}`;

function documentFixture(overrides: Partial<ProfileDocument> = {}): ProfileDocument {
  return {
    schemaVersion: "PROFILE_DOCUMENT_V019",
    profileVersionId: id("1"),
    versionNumber: 1,
    status: "DRAFT",
    revision: 3,
    snapshotHash: null,
    frozenAt: null,
    readiness: {
      schemaVersion: "PROFILE_READINESS_V019",
      freezeReady: false,
      requiredScopeCount: 2,
      declaredRequiredScopeCount: 1,
      missingDeclarations: [{ educationContextId: null, domain: "COURSE_HISTORY" }],
      declarations: [{ completenessId: id("2"), educationContextId: null, domain: "EDUCATION_HISTORY", completeness: "PARTIAL", explanation: "第二份成绩单尚未录入" }],
      mappingReadiness: [],
    },
    evidenceItems: [],
    degrees: [],
    courses: [],
    testScores: [],
    experiences: [],
    skills: [],
    experienceSkills: [],
    goals: [],
    preferences: [],
    mappings: [],
    ...overrides,
  };
}

describe("Profile Draft Core semantics", () => {
  it("keeps record counts separate from authoritative completeness declarations", () => {
    const empty = profileOverview(documentFixture());
    const manyCourses = profileOverview(documentFixture({
      courses: Array.from({ length: 20 }, (_, index) => ({ courseId: id(String(index + 10)) })),
    }));

    expect(empty.completenessScopes).toEqual(manyCourses.completenessScopes);
    expect(empty.counts.courses).toBe(0);
    expect(manyCourses.counts.courses).toBe(20);
    expect(manyCourses.completenessScopes.map((scope) => scope.completeness)).toEqual(["PARTIAL", "MISSING_DECLARATION"]);
  });

  it("treats COMPLETE, PARTIAL, UNKNOWN, and missing declaration as distinct states", () => {
    const scopes = completenessScopes(documentFixture({
      readiness: {
        schemaVersion: "PROFILE_READINESS_V019",
        freezeReady: false,
        requiredScopeCount: 4,
        declaredRequiredScopeCount: 3,
        missingDeclarations: [{ educationContextId: null, domain: "GOALS" }],
        declarations: [
          { completenessId: id("3"), educationContextId: null, domain: "EDUCATION_HISTORY", completeness: "COMPLETE", explanation: null },
          { completenessId: id("4"), educationContextId: null, domain: "EXPERIENCE_HISTORY", completeness: "PARTIAL", explanation: "More to add" },
          { completenessId: id("5"), educationContextId: null, domain: "SKILL_HISTORY", completeness: "UNKNOWN", explanation: "Cannot confirm" },
        ],
        mappingReadiness: [],
      },
    }));

    expect(scopes.map((scope) => scope.completeness).sort()).toEqual(["COMPLETE", "MISSING_DECLARATION", "PARTIAL", "UNKNOWN"]);
    expect(completenessDescription("UNKNOWN")).toContain("cannot currently confirm");
    expect(completenessDescription("MISSING_DECLARATION")).toContain("No completeness declaration");
  });

  it("never turns an evidence row into a verification claim", () => {
    const selfReport = { evidenceId: id("6"), evidenceType: "SELF_REPORT", locator: null, contentHash: null, observedAt: "2026-08-23T00:00:00Z" } satisfies ProfileEvidenceItem;
    const transcript = { ...selfReport, evidenceId: id("7"), evidenceType: "TRANSCRIPT" } satisfies ProfileEvidenceItem;
    expect(sourceDescription(selfReport)).toBe("Student-provided information; not externally verified.");
    expect(sourceDescription(transcript)).toBe("Information referenced from a transcript source.");
    expect(sourceDescription(transcript)).not.toContain("Officially verified");
  });

  it("joins only projected labels referenced by the selected record without a UUID label table", () => {
    const recordId = id("60");
    const activeConceptId = id("61");
    const historicalConceptId = id("62");
    const unrelatedConceptId = id("63");
    const document = documentFixture({
      mappings: [
        { mappingId: id("64"), recordType: "DEGREE", recordId, conceptId: historicalConceptId, mappingStatus: "PROPOSED", evidenceId: null },
        { mappingId: id("65"), recordType: "DEGREE", recordId, conceptId: activeConceptId, mappingStatus: "VERIFIED", evidenceId: null },
      ],
    });
    const taxonomy = {
      schemaVersion: "PROFILE_TAXONOMY_PROJECTION_V022" as const,
      releaseCode: "v0.2",
      releaseOrdinal: 2,
      concepts: [
        { conceptId: activeConceptId, canonicalKey: "COURSE_CONCEPT.CALCULUS", conceptKind: "COURSE_CONCEPT" as const, displayName: "Calculus", activeAtRelease: true },
        { conceptId: historicalConceptId, canonicalKey: "FIELD.ECONOMICS", conceptKind: "FIELD" as const, displayName: "Economics", activeAtRelease: false },
        { conceptId: unrelatedConceptId, canonicalKey: "SUBFIELD.ECONOMETRICS", conceptKind: "SUBFIELD" as const, displayName: "Econometrics", activeAtRelease: true },
      ],
    };

    expect(mappingLabelsFor(document, taxonomy, recordId)).toEqual(taxonomy.concepts.slice(0, 2));
    expect(mappingLabelsFor(document, taxonomy, id("66"))).toEqual([]);
    expect(mappingLabelsFor(document, null, recordId)).toEqual([]);
  });
});

describe("replacement-style mutation payloads", () => {
  it("preserves the complete source payload", () => {
    const source = { evidenceId: id("8"), evidenceType: "TRANSCRIPT", locator: "成绩单原件", contentHash: "a".repeat(64), observedAt: "2026-08-23T08:30:00Z" } satisfies ProfileEvidenceItem;
    expect(evidenceUpdatePayload(source)).toEqual(source);
  });

  it("preserves Chinese education text and a non-4.0 GPA without inference or conversion", () => {
    const degree = {
      degreeId: id("9"), institutionName: "浙江大学", degreeName: "工学学士",
      degreeLevel: "BACHELORS", degreeStatus: "COMPLETED", startDate: "2020-09-01",
      completionDate: "2024-06-30", countryCode: "CN", gpaValue: 85, gpaScale: 100,
      evidenceId: id("8"),
    } satisfies ProfileDegree;
    const payload = degreeUpdatePayload(degree);
    expect(payload).toEqual(degree);
    expect(payload.gpaValue).toBe(85);
    expect(payload.gpaScale).toBe(100);
    expect(payload).not.toHaveProperty("major");
    expect(payload).not.toHaveProperty("prestige");
  });

  it("preserves Chinese course text, raw credits, and grade representations", () => {
    const course = {
      courseId: id("10"), degreeId: id("9"), courseCode: "MATH-101", courseTitle: "概率论与数理统计",
      courseStatus: "COMPLETED", term: "2024 秋", completionDate: "2024-12-20", credits: 4,
      gradeValue: 92, gradeScale: 100, gradeText: "优秀", evidenceId: id("8"),
    } satisfies ProfileCourse;
    const payload = courseUpdatePayload(course);
    expect(payload).toEqual(course);
    expect(payload.credits).toBe(4);
    expect(payload.gradeValue).toBe(92);
    expect(payload.gradeScale).toBe(100);
    expect(payload.gradeText).toBe("优秀");
    expect(payload).not.toHaveProperty("usCredits");
    expect(payload).not.toHaveProperty("courseEquivalency");
  });
});
