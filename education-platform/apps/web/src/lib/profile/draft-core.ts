import type { ProfileCommandPayloads, ProfileDocument } from "./contracts";

export const PROFILE_DRAFT_SECTIONS = [
  "overview",
  "sources",
  "education",
  "courses",
  "completeness",
  "review",
] as const;

export type ProfileDraftSection = (typeof PROFILE_DRAFT_SECTIONS)[number];

export type ProfileEvidenceItem = Readonly<{
  evidenceId: string;
  evidenceType: "SELF_REPORT" | "TRANSCRIPT" | "TEST_REPORT" | "RESUME" | "OTHER";
  locator: string | null;
  contentHash: string | null;
  observedAt: string;
}>;

export type ProfileDegree = Readonly<{
  degreeId: string;
  institutionName: string;
  degreeName: string;
  degreeLevel: "BACHELORS" | "MASTERS" | "DOCTORAL" | "CERTIFICATE" | "OTHER";
  degreeStatus: "IN_PROGRESS" | "COMPLETED" | "WITHDRAWN";
  startDate: string | null;
  completionDate: string | null;
  countryCode: string | null;
  gpaValue: number | null;
  gpaScale: number | null;
  evidenceId: string;
}>;

export type ProfileCourse = Readonly<{
  courseId: string;
  degreeId: string | null;
  courseCode: string | null;
  courseTitle: string;
  courseStatus: "PLANNED" | "IN_PROGRESS" | "COMPLETED" | "WITHDRAWN";
  term: string | null;
  completionDate: string | null;
  credits: number | null;
  gradeValue: number | null;
  gradeScale: number | null;
  gradeText: string | null;
  evidenceId: string;
}>;

export type ProfileCompletenessScope = Readonly<{
  key: string;
  educationContextId: string | null;
  domain: ProfileDocument["readiness"]["missingDeclarations"][number]["domain"];
  completeness: "COMPLETE" | "PARTIAL" | "UNKNOWN" | "MISSING_DECLARATION";
  explanation: string | null;
}>;

export type ProfileOverview = Readonly<{
  counts: Readonly<{
    sources: number;
    education: number;
    courses: number;
    tests: number;
    experiences: number;
    skills: number;
    goals: number;
    preferences: number;
  }>;
  completenessScopes: readonly ProfileCompletenessScope[];
}>;

export type EvidenceUsage = Readonly<{
  total: number;
  education: number;
  courses: number;
  tests: number;
  experiences: number;
  skills: number;
  mappings: number;
}>;

export const PROFILE_DOMAIN_LABELS: Readonly<Record<ProfileCompletenessScope["domain"], string>> = Object.freeze({
  EDUCATION_HISTORY: "Education history",
  COURSE_HISTORY: "Course history",
  COURSE_MAPPING: "Course mapping",
  TEST_HISTORY: "Test history",
  EXPERIENCE_HISTORY: "Experience history",
  SKILL_HISTORY: "Skill history",
  PREFERENCES: "Preferences",
  GOALS: "Goals",
});

function scopeKey(educationContextId: string | null, domain: string): string {
  return `${educationContextId ?? "GLOBAL"}:${domain}`;
}

export function evidenceItems(document: ProfileDocument): readonly ProfileEvidenceItem[] {
  return document.evidenceItems as readonly ProfileEvidenceItem[];
}

export function degrees(document: ProfileDocument): readonly ProfileDegree[] {
  return document.degrees as readonly ProfileDegree[];
}

export function courses(document: ProfileDocument): readonly ProfileCourse[] {
  return document.courses as readonly ProfileCourse[];
}

export function completenessScopes(document: ProfileDocument): readonly ProfileCompletenessScope[] {
  const declarations = new Map(
    document.readiness.declarations.map((declaration) => [
      scopeKey(declaration.educationContextId, declaration.domain),
      declaration,
    ]),
  );
  const required = new Map<string, ProfileCompletenessScope>();

  for (const missing of document.readiness.missingDeclarations) {
    const key = scopeKey(missing.educationContextId, missing.domain);
    required.set(key, Object.freeze({
      key,
      educationContextId: missing.educationContextId,
      domain: missing.domain,
      completeness: "MISSING_DECLARATION",
      explanation: null,
    }));
  }

  for (const declaration of declarations.values()) {
    const key = scopeKey(declaration.educationContextId, declaration.domain);
    required.set(key, Object.freeze({
      key,
      educationContextId: declaration.educationContextId,
      domain: declaration.domain,
      completeness: declaration.completeness,
      explanation: declaration.explanation,
    }));
  }

  return Object.freeze([...required.values()].sort((left, right) => {
    const domainOrder = Object.keys(PROFILE_DOMAIN_LABELS);
    const byDomain = domainOrder.indexOf(left.domain) - domainOrder.indexOf(right.domain);
    if (byDomain !== 0) return byDomain;
    return (left.educationContextId ?? "").localeCompare(right.educationContextId ?? "");
  }));
}

export function profileOverview(document: ProfileDocument): ProfileOverview {
  return Object.freeze({
    counts: Object.freeze({
      sources: document.evidenceItems.length,
      education: document.degrees.length,
      courses: document.courses.length,
      tests: document.testScores.length,
      experiences: document.experiences.length,
      skills: document.skills.length,
      goals: document.goals.length,
      preferences: document.preferences.length,
    }),
    completenessScopes: completenessScopes(document),
  });
}

export function evidenceUsage(document: ProfileDocument, evidenceId: string): EvidenceUsage {
  const count = (records: readonly Record<string, unknown>[]) => records.filter((record) => record.evidenceId === evidenceId).length;
  const usage = Object.freeze({
    education: count(document.degrees),
    courses: count(document.courses),
    tests: count(document.testScores),
    experiences: count(document.experiences),
    skills: count(document.skills),
    mappings: count(document.mappings),
  });
  return Object.freeze({ ...usage, total: Object.values(usage).reduce((sum, value) => sum + value, 0) });
}

export function degreeLabel(document: ProfileDocument, degreeId: string | null): string {
  if (degreeId === null) return "Profile-wide course history";
  const degree = degrees(document).find((candidate) => candidate.degreeId === degreeId);
  return degree ? `${degree.institutionName} — ${degree.degreeName}` : "Education record unavailable";
}

export function mappingReadinessFor(document: ProfileDocument, recordId: string) {
  return document.readiness.mappingReadiness.find((mapping) => mapping.recordId === recordId) ?? null;
}

export function evidenceUpdatePayload(item: ProfileEvidenceItem): ProfileCommandPayloads["EVIDENCE_UPDATE"] {
  return Object.freeze({
    evidenceId: item.evidenceId,
    evidenceType: item.evidenceType,
    locator: item.locator,
    contentHash: item.contentHash,
    observedAt: item.observedAt,
  });
}

export function degreeUpdatePayload(degree: ProfileDegree): ProfileCommandPayloads["DEGREE_UPDATE"] {
  return Object.freeze({
    degreeId: degree.degreeId,
    institutionName: degree.institutionName,
    degreeName: degree.degreeName,
    degreeLevel: degree.degreeLevel,
    degreeStatus: degree.degreeStatus,
    startDate: degree.startDate,
    completionDate: degree.completionDate,
    countryCode: degree.countryCode,
    gpaValue: degree.gpaValue,
    gpaScale: degree.gpaScale,
    evidenceId: degree.evidenceId,
  });
}

export function courseUpdatePayload(course: ProfileCourse): ProfileCommandPayloads["COURSE_UPDATE"] {
  return Object.freeze({
    courseId: course.courseId,
    degreeId: course.degreeId,
    courseCode: course.courseCode,
    courseTitle: course.courseTitle,
    courseStatus: course.courseStatus,
    term: course.term,
    completionDate: course.completionDate,
    credits: course.credits,
    gradeValue: course.gradeValue,
    gradeScale: course.gradeScale,
    gradeText: course.gradeText,
    evidenceId: course.evidenceId,
  });
}

export function sourceDescription(item: ProfileEvidenceItem): string {
  if (item.evidenceType === "SELF_REPORT") return "Student-provided information; not externally verified.";
  if (item.evidenceType === "TRANSCRIPT") return "Information referenced from a transcript source.";
  if (item.evidenceType === "TEST_REPORT") return "Information referenced from a test report source.";
  if (item.evidenceType === "RESUME") return "Information referenced from a resume source.";
  return "Information referenced from another student-identified source.";
}

export function completenessDescription(value: ProfileCompletenessScope["completeness"]): string {
  if (value === "COMPLETE") return "You have explicitly declared that this data scope is complete.";
  if (value === "PARTIAL") return "You have provided some information, but you have declared that this scope is not complete.";
  if (value === "UNKNOWN") return "You cannot currently confirm whether this data scope is complete.";
  return "No completeness declaration has been provided for this required scope.";
}
