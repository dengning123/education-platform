import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { describe, expect, it } from "vitest";

import {
  PROFILE_COMMAND_KEY_CONTRACT,
  PROFILE_COMMANDS,
  parseMutationRequest,
  parseProfileAccount,
  parseProfileDocument,
  parseProfileMutationCommand,
  parseProfileOperationResult,
} from "./contracts";

const id = (suffix: string) => `00000000-0000-4000-8000-${suffix.padStart(12, "0")}`;

const commandExamples: Record<string, Record<string, unknown>> = {
  COMPLETENESS_UPSERT: { educationContextId: null, domain: "GOALS", completeness: "PARTIAL", explanation: "Still gathering details" },
  COMPLETENESS_DELETE: { educationContextId: null, domain: "GOALS" },
  EVIDENCE_CREATE: { evidenceType: "SELF_REPORT", locator: null, contentHash: null, observedAt: "2026-08-23T12:00:00Z" },
  EVIDENCE_UPDATE: { evidenceId: id("1"), evidenceType: "TRANSCRIPT", locator: "local-reference", contentHash: "a".repeat(64), observedAt: "2026-08-23T12:00:00Z" },
  EVIDENCE_DELETE: { evidenceId: id("1") },
  DEGREE_CREATE: { institutionName: "Example University", degreeName: "BS", degreeLevel: "BACHELORS", degreeStatus: "COMPLETED", startDate: "2020-01-01", completionDate: "2024-01-01", countryCode: "US", gpaValue: 3.8, gpaScale: 4, evidenceId: id("1") },
  DEGREE_UPDATE: { degreeId: id("2"), institutionName: "Example University", degreeName: "BS", degreeLevel: "BACHELORS", degreeStatus: "COMPLETED", startDate: null, completionDate: null, countryCode: null, gpaValue: null, gpaScale: null, evidenceId: id("1") },
  DEGREE_DELETE: { degreeId: id("2") },
  COURSE_CREATE: { degreeId: id("2"), courseCode: "MATH-1", courseTitle: "Calculus", courseStatus: "COMPLETED", term: "Fall", completionDate: "2023-12-01", credits: 3, gradeValue: 4, gradeScale: 4, gradeText: "A", evidenceId: id("1") },
  COURSE_UPDATE: { courseId: id("3"), degreeId: null, courseCode: null, courseTitle: "Calculus", courseStatus: "COMPLETED", term: null, completionDate: null, credits: null, gradeValue: null, gradeScale: null, gradeText: null, evidenceId: id("1") },
  COURSE_DELETE: { courseId: id("3") },
  TEST_SCORE_CREATE: { assessmentConceptId: id("4"), testDate: "2025-10-01", totalScore: 330, sectionScores: { quantitative: 168 }, evidenceId: id("1") },
  TEST_SCORE_UPDATE: { testScoreId: id("5"), assessmentConceptId: id("4"), testDate: "2025-10-01", totalScore: null, sectionScores: { quantitative: 168 }, evidenceId: id("1") },
  TEST_SCORE_DELETE: { testScoreId: id("5") },
  EXPERIENCE_CREATE: { experienceType: "INTERNSHIP", organizationName: "Example", roleTitle: "Analyst", startDate: "2025-01-01", endDate: "2025-05-01", hoursPerWeek: 20, description: "Structured work", evidenceId: id("1") },
  EXPERIENCE_UPDATE: { experienceId: id("6"), experienceType: "RESEARCH", organizationName: null, roleTitle: "Assistant", startDate: null, endDate: null, hoursPerWeek: null, description: null, evidenceId: id("1") },
  EXPERIENCE_DELETE: { experienceId: id("6") },
  SKILL_CREATE: { skillConceptId: id("7"), proficiencyLevel: 4, yearsExperience: 2, evidenceId: id("1") },
  SKILL_UPDATE: { skillId: id("8"), skillConceptId: id("7"), proficiencyLevel: null, yearsExperience: null, evidenceId: id("1") },
  SKILL_DELETE: { skillId: id("8") },
  EXPERIENCE_SKILL_LINK: { experienceId: id("6"), skillId: id("8") },
  EXPERIENCE_SKILL_UNLINK: { experienceId: id("6"), skillId: id("8") },
  GOAL_CREATE: { goalType: "CAREER", conceptId: null, goalText: "Quantitative analyst", priority: 1 },
  GOAL_UPDATE: { goalId: id("9"), goalType: "FIELD", conceptId: id("10"), goalText: null, priority: 2 },
  GOAL_DELETE: { goalId: id("9") },
  PREFERENCE_CREATE: { preferenceType: "LOCATION", value: { countryCodes: ["US", "CA"] }, priority: 1 },
  PREFERENCE_UPDATE: { preferenceId: id("11"), preferenceType: "BUDGET", value: { currencyCode: "USD", maximumAmount: 80000 }, priority: 2 },
  PREFERENCE_DELETE: { preferenceId: id("11") },
};

function sqlArrayPattern(keys: readonly string[]): RegExp {
  return new RegExp(`array\\[\\s*${keys.map((key) => `'${key}'`).join("\\s*,\\s*")}\\s*\\]`, "s");
}

async function migration019(): Promise<string> {
  const webRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../../");
  return readFile(resolve(webRoot, "../../supabase/migrations/202608230019_profile_draft_freeze_capability.sql"), "utf8");
}

describe("Profile command contract", () => {
  it("accepts every browser-authorized command with its closed typed payload", () => {
    expect(Object.keys(commandExamples).sort()).toEqual([...PROFILE_COMMANDS].sort());
    for (const command of PROFILE_COMMANDS) {
      expect(parseProfileMutationCommand({ command, payload: commandExamples[command] })).toMatchObject({ command });
    }
  });

  it("rejects unknown commands, fields, arbitrary metadata, and reviewer/control fields", () => {
    expect(() => parseProfileMutationCommand({ command: "COMPETITIVENESS_SET", payload: {} })).toThrow("INVALID_REQUEST");
    expect(() => parseProfileMutationCommand({ command: "GOAL_CREATE", payload: { ...commandExamples.GOAL_CREATE, competitivenessWeight: 0.5 } })).toThrow("INVALID_REQUEST");
    expect(() => parseProfileMutationCommand({ command: "EVIDENCE_CREATE", payload: { ...commandExamples.EVIDENCE_CREATE, metadata: { arbitrary: true } } })).toThrow("INVALID_REQUEST");
    expect(() => parseProfileMutationCommand({ command: "DEGREE_CREATE", payload: { ...commandExamples.DEGREE_CREATE, reviewedBy: id("12") } })).toThrow("INVALID_REQUEST");
  });

  it("rejects malformed nested and envelope values", () => {
    expect(() => parseProfileMutationCommand({ command: "TEST_SCORE_CREATE", payload: { ...commandExamples.TEST_SCORE_CREATE, sectionScores: { secretSection: 100 } } })).toThrow("INVALID_REQUEST");
    expect(() => parseProfileMutationCommand({ command: "PREFERENCE_CREATE", payload: { preferenceType: "LOCATION", value: { countryCodes: ["USA"] }, priority: 1 } })).toThrow("INVALID_REQUEST");
    expect(() => parseMutationRequest({ profileVersionId: id("20"), operationId: id("21"), expectedRevision: -1, command: "GOAL_CREATE", payload: commandExamples.GOAL_CREATE })).toThrow("INVALID_REQUEST");
  });

  it("matches the SQL enum and each branch's allowed/required key arrays", async () => {
    const sql = await migration019();
    const enumBody = sql.match(/create type public\.profile_draft_command_v019 as enum \((.*?)\);/s)?.[1] ?? "";
    const sqlCommands = [...enumBody.matchAll(/'([A-Z_]+)'/g)].map((match) => match[1]);
    expect(sqlCommands).toEqual(PROFILE_COMMANDS);

    const branchMarkers = [...sql.matchAll(/(?:if|elsif) p_command(?: =| in)[\s\S]*? then/g)];
    for (const command of PROFILE_COMMANDS) {
      const markerIndex = branchMarkers.findIndex((marker) => marker[0].includes(`'${command}'`));
      expect(markerIndex, command).toBeGreaterThanOrEqual(0);
      const start = branchMarkers[markerIndex].index ?? 0;
      const end = branchMarkers[markerIndex + 1]?.index ?? sql.indexOf("  else\n    raise exception", start);
      const block = sql.slice(start, end);
      expect(block, `${command} allowed keys`).toMatch(sqlArrayPattern(PROFILE_COMMAND_KEY_CONTRACT[command].allowed));
      expect(block, `${command} required keys`).toMatch(sqlArrayPattern(PROFILE_COMMAND_KEY_CONTRACT[command].required));
    }
  });
});

const emptyReadiness = {
  schemaVersion: "PROFILE_READINESS_V019",
  freezeReady: false,
  requiredScopeCount: 8,
  declaredRequiredScopeCount: 0,
  missingDeclarations: [{ educationContextId: null, domain: "GOALS" }],
  declarations: [],
  mappingReadiness: [],
};

const draftDocument = {
  schemaVersion: "PROFILE_DOCUMENT_V019",
  profileVersionId: id("30"), versionNumber: 1, status: "DRAFT", revision: 0,
  snapshotHash: null, frozenAt: null, readiness: emptyReadiness,
  evidenceItems: [], degrees: [], courses: [], testScores: [], experiences: [], skills: [], experienceSkills: [], goals: [], preferences: [], mappings: [],
};

describe("Profile response DTO contract", () => {
  it("accepts only the closed account, document, and operation result schemas", () => {
    expect(parseProfileAccount({ schemaVersion: "PROFILE_ACCOUNT_V019", accountState: "ACTIVE", hasCurrentDraft: false })).toMatchObject({ hasCurrentDraft: false });
    expect(parseProfileDocument(draftDocument)).toMatchObject({ status: "DRAFT", revision: 0 });
    expect(parseProfileOperationResult({ schemaVersion: "PROFILE_OPERATION_RESULT_V019", operation: "CREATE_OR_RESUME", profileVersionId: id("30"), versionNumber: 1, status: "DRAFT", revision: 0 })).toMatchObject({ operation: "CREATE_OR_RESUME" });
  });

  it("rejects internal control fields and invalid frozen state", () => {
    expect(() => parseProfileDocument({ ...draftDocument, reviewedBy: id("31") })).toThrow("INVALID_REQUEST");
    expect(() => parseProfileDocument({ ...draftDocument, status: "FROZEN" })).toThrow("INVALID_REQUEST");
    expect(() => parseProfileAccount({ schemaVersion: "PROFILE_ACCOUNT_V019", accountState: "ACTIVE", hasCurrentDraft: false, studentId: id("32") })).toThrow("INVALID_REQUEST");
  });

  it("rejects operation/schema drift, impossible status, and open resource keys", () => {
    const create = { schemaVersion: "PROFILE_OPERATION_RESULT_V019", operation: "CREATE_OR_RESUME", profileVersionId: id("30"), versionNumber: 1, status: "DRAFT", revision: 0 };
    expect(() => parseProfileOperationResult({ ...create, schemaVersion: "PROFILE_OPERATION_RESULT_V020" })).toThrow("INVALID_REQUEST");
    expect(() => parseProfileOperationResult({ ...create, status: "FROZEN" })).toThrow("INVALID_REQUEST");
    expect(() => parseProfileOperationResult({ ...create, versionNumber: 0 })).toThrow("INVALID_REQUEST");

    const link = {
      schemaVersion: "PROFILE_OPERATION_RESULT_V019", operation: "MUTATE", command: "EXPERIENCE_SKILL_LINK",
      profileVersionId: id("30"), revision: 1, resourceId: null,
      resourceKey: { experienceId: id("33"), skillId: id("34") },
    };
    expect(parseProfileOperationResult(link)).toMatchObject({ operation: "MUTATE", resourceKey: link.resourceKey });
    expect(() => parseProfileOperationResult({ ...link, resourceKey: { ...link.resourceKey, studentId: id("35") } })).toThrow("INVALID_REQUEST");
  });
});
