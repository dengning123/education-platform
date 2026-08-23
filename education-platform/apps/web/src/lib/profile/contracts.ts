export const PROFILE_UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const SHA256_PATTERN = /^[a-f0-9]{64}$/;

export const PROFILE_DATA_DOMAINS = [
  "EDUCATION_HISTORY",
  "COURSE_HISTORY",
  "COURSE_MAPPING",
  "TEST_HISTORY",
  "EXPERIENCE_HISTORY",
  "SKILL_HISTORY",
  "PREFERENCES",
  "GOALS",
] as const;

export const PROFILE_COMPLETENESS_VALUES = ["COMPLETE", "PARTIAL", "UNKNOWN"] as const;
export const PROFILE_EVIDENCE_TYPES = ["SELF_REPORT", "TRANSCRIPT", "TEST_REPORT", "RESUME", "OTHER"] as const;
export const PROFILE_DEGREE_LEVELS = ["BACHELORS", "MASTERS", "DOCTORAL", "CERTIFICATE", "OTHER"] as const;
export const PROFILE_DEGREE_STATUSES = ["IN_PROGRESS", "COMPLETED", "WITHDRAWN"] as const;
export const PROFILE_COURSE_STATUSES = ["PLANNED", "IN_PROGRESS", "COMPLETED", "WITHDRAWN"] as const;
export const PROFILE_EXPERIENCE_TYPES = [
  "EMPLOYMENT",
  "INTERNSHIP",
  "RESEARCH",
  "PROJECT",
  "LEADERSHIP",
  "VOLUNTEERING",
  "OTHER",
] as const;
export const PROFILE_GOAL_TYPES = ["CAREER", "INDUSTRY", "FIELD", "OTHER"] as const;
export const PROFILE_PREFERENCE_TYPES = ["LOCATION", "DELIVERY_MODE", "BUDGET", "PROGRAM_LENGTH"] as const;
export const PROFILE_MAPPING_STATUSES = ["PROPOSED", "VERIFIED", "REJECTED", "RETIRED"] as const;
export const PROFILE_SECTION_SCORE_KEYS = [
  "quantitative",
  "verbal",
  "analyticalWriting",
  "integratedReasoning",
  "reading",
  "listening",
  "speaking",
  "writing",
  "math",
  "english",
  "science",
  "composite",
] as const;

type DataDomain = (typeof PROFILE_DATA_DOMAINS)[number];
type Completeness = (typeof PROFILE_COMPLETENESS_VALUES)[number];
type EvidenceType = (typeof PROFILE_EVIDENCE_TYPES)[number];
type DegreeLevel = (typeof PROFILE_DEGREE_LEVELS)[number];
type DegreeStatus = (typeof PROFILE_DEGREE_STATUSES)[number];
type CourseStatus = (typeof PROFILE_COURSE_STATUSES)[number];
type ExperienceType = (typeof PROFILE_EXPERIENCE_TYPES)[number];
type GoalType = (typeof PROFILE_GOAL_TYPES)[number];
type MappingStatus = (typeof PROFILE_MAPPING_STATUSES)[number];

type OptionalText = string | null | undefined;
type OptionalNumber = number | null | undefined;
type OptionalUuid = string | null | undefined;

export type ProfilePreferenceValue =
  | Readonly<{ countryCodes: readonly string[] }>
  | Readonly<{ modes: readonly ("IN_PERSON" | "ONLINE" | "HYBRID")[] }>
  | Readonly<{ currencyCode: string; maximumAmount: number }>
  | Readonly<{ minimumMonths?: number; maximumMonths?: number }>;

export interface ProfileCommandPayloads {
  COMPLETENESS_UPSERT: Readonly<{ educationContextId?: OptionalUuid; domain: DataDomain; completeness: Completeness; explanation?: OptionalText }>;
  COMPLETENESS_DELETE: Readonly<{ educationContextId?: OptionalUuid; domain: DataDomain }>;
  EVIDENCE_CREATE: Readonly<{ evidenceType: EvidenceType; locator?: OptionalText; contentHash?: OptionalText; observedAt?: OptionalText }>;
  EVIDENCE_UPDATE: Readonly<{ evidenceId: string; evidenceType: EvidenceType; locator?: OptionalText; contentHash?: OptionalText; observedAt?: OptionalText }>;
  EVIDENCE_DELETE: Readonly<{ evidenceId: string }>;
  DEGREE_CREATE: Readonly<{ institutionName: string; degreeName: string; degreeLevel: DegreeLevel; degreeStatus: DegreeStatus; startDate?: OptionalText; completionDate?: OptionalText; countryCode?: OptionalText; gpaValue?: OptionalNumber; gpaScale?: OptionalNumber; evidenceId: string }>;
  DEGREE_UPDATE: ProfileCommandPayloads["DEGREE_CREATE"] & Readonly<{ degreeId: string }>;
  DEGREE_DELETE: Readonly<{ degreeId: string }>;
  COURSE_CREATE: Readonly<{ degreeId?: OptionalUuid; courseCode?: OptionalText; courseTitle: string; courseStatus: CourseStatus; term?: OptionalText; completionDate?: OptionalText; credits?: OptionalNumber; gradeValue?: OptionalNumber; gradeScale?: OptionalNumber; gradeText?: OptionalText; evidenceId: string }>;
  COURSE_UPDATE: ProfileCommandPayloads["COURSE_CREATE"] & Readonly<{ courseId: string }>;
  COURSE_DELETE: Readonly<{ courseId: string }>;
  TEST_SCORE_CREATE: Readonly<{ assessmentConceptId: string; testDate: string; totalScore?: OptionalNumber; sectionScores?: Readonly<Record<string, number>> | null; evidenceId: string }>;
  TEST_SCORE_UPDATE: ProfileCommandPayloads["TEST_SCORE_CREATE"] & Readonly<{ testScoreId: string }>;
  TEST_SCORE_DELETE: Readonly<{ testScoreId: string }>;
  EXPERIENCE_CREATE: Readonly<{ experienceType: ExperienceType; organizationName?: OptionalText; roleTitle: string; startDate?: OptionalText; endDate?: OptionalText; hoursPerWeek?: OptionalNumber; description?: OptionalText; evidenceId: string }>;
  EXPERIENCE_UPDATE: ProfileCommandPayloads["EXPERIENCE_CREATE"] & Readonly<{ experienceId: string }>;
  EXPERIENCE_DELETE: Readonly<{ experienceId: string }>;
  SKILL_CREATE: Readonly<{ skillConceptId: string; proficiencyLevel?: OptionalNumber; yearsExperience?: OptionalNumber; evidenceId: string }>;
  SKILL_UPDATE: ProfileCommandPayloads["SKILL_CREATE"] & Readonly<{ skillId: string }>;
  SKILL_DELETE: Readonly<{ skillId: string }>;
  EXPERIENCE_SKILL_LINK: Readonly<{ experienceId: string; skillId: string }>;
  EXPERIENCE_SKILL_UNLINK: Readonly<{ experienceId: string; skillId: string }>;
  GOAL_CREATE: Readonly<{ goalType: GoalType; conceptId?: OptionalUuid; goalText?: OptionalText; priority: number }>;
  GOAL_UPDATE: ProfileCommandPayloads["GOAL_CREATE"] & Readonly<{ goalId: string }>;
  GOAL_DELETE: Readonly<{ goalId: string }>;
  PREFERENCE_CREATE: Readonly<{ preferenceType: (typeof PROFILE_PREFERENCE_TYPES)[number]; value: ProfilePreferenceValue; priority: number }>;
  PREFERENCE_UPDATE: ProfileCommandPayloads["PREFERENCE_CREATE"] & Readonly<{ preferenceId: string }>;
  PREFERENCE_DELETE: Readonly<{ preferenceId: string }>;
}

export type ProfileCommand = keyof ProfileCommandPayloads;
export type ProfileMutationCommand = {
  [Command in ProfileCommand]: Readonly<{
    command: Command;
    payload: ProfileCommandPayloads[Command];
  }>;
}[ProfileCommand];

type FieldKind =
  | "date"
  | "enum"
  | "hash"
  | "integer"
  | "number"
  | "preferenceValue"
  | "sectionScores"
  | "string"
  | "timestamp"
  | "uuid";

type FieldRule = Readonly<{
  kind: FieldKind;
  required?: true;
  nullable?: true;
  values?: readonly string[];
}>;

const required = (kind: FieldKind, values?: readonly string[]): FieldRule => ({ kind, required: true, values });
const optional = (kind: FieldKind, values?: readonly string[]): FieldRule => ({ kind, nullable: true, values });

const evidenceCreate = {
  evidenceType: required("enum", PROFILE_EVIDENCE_TYPES),
  locator: optional("string"),
  contentHash: optional("hash"),
  observedAt: optional("timestamp"),
} as const;
const degreeCreate = {
  institutionName: required("string"), degreeName: required("string"),
  degreeLevel: required("enum", PROFILE_DEGREE_LEVELS), degreeStatus: required("enum", PROFILE_DEGREE_STATUSES),
  startDate: optional("date"), completionDate: optional("date"), countryCode: optional("string"),
  gpaValue: optional("number"), gpaScale: optional("number"), evidenceId: required("uuid"),
} as const;
const courseCreate = {
  degreeId: optional("uuid"), courseCode: optional("string"), courseTitle: required("string"),
  courseStatus: required("enum", PROFILE_COURSE_STATUSES), term: optional("string"), completionDate: optional("date"),
  credits: optional("number"), gradeValue: optional("number"), gradeScale: optional("number"),
  gradeText: optional("string"), evidenceId: required("uuid"),
} as const;
const testCreate = {
  assessmentConceptId: required("uuid"), testDate: required("date"), totalScore: optional("number"),
  sectionScores: optional("sectionScores"), evidenceId: required("uuid"),
} as const;
const experienceCreate = {
  experienceType: required("enum", PROFILE_EXPERIENCE_TYPES), organizationName: optional("string"),
  roleTitle: required("string"), startDate: optional("date"), endDate: optional("date"),
  hoursPerWeek: optional("number"), description: optional("string"), evidenceId: required("uuid"),
} as const;
const skillCreate = {
  skillConceptId: required("uuid"), proficiencyLevel: optional("integer"),
  yearsExperience: optional("number"), evidenceId: required("uuid"),
} as const;
const goalCreate = {
  goalType: required("enum", PROFILE_GOAL_TYPES), conceptId: optional("uuid"),
  goalText: optional("string"), priority: required("integer"),
} as const;
const preferenceCreate = {
  preferenceType: required("enum", PROFILE_PREFERENCE_TYPES),
  value: required("preferenceValue"), priority: required("integer"),
} as const;

export const PROFILE_COMMAND_SCHEMAS: Readonly<Record<ProfileCommand, Readonly<Record<string, FieldRule>>>> = Object.freeze({
  COMPLETENESS_UPSERT: { educationContextId: optional("uuid"), domain: required("enum", PROFILE_DATA_DOMAINS), completeness: required("enum", PROFILE_COMPLETENESS_VALUES), explanation: optional("string") },
  COMPLETENESS_DELETE: { educationContextId: optional("uuid"), domain: required("enum", PROFILE_DATA_DOMAINS) },
  EVIDENCE_CREATE: evidenceCreate,
  EVIDENCE_UPDATE: { evidenceId: required("uuid"), ...evidenceCreate },
  EVIDENCE_DELETE: { evidenceId: required("uuid") },
  DEGREE_CREATE: degreeCreate,
  DEGREE_UPDATE: { degreeId: required("uuid"), ...degreeCreate },
  DEGREE_DELETE: { degreeId: required("uuid") },
  COURSE_CREATE: courseCreate,
  COURSE_UPDATE: { courseId: required("uuid"), ...courseCreate },
  COURSE_DELETE: { courseId: required("uuid") },
  TEST_SCORE_CREATE: testCreate,
  TEST_SCORE_UPDATE: { testScoreId: required("uuid"), ...testCreate },
  TEST_SCORE_DELETE: { testScoreId: required("uuid") },
  EXPERIENCE_CREATE: experienceCreate,
  EXPERIENCE_UPDATE: { experienceId: required("uuid"), ...experienceCreate },
  EXPERIENCE_DELETE: { experienceId: required("uuid") },
  SKILL_CREATE: skillCreate,
  SKILL_UPDATE: { skillId: required("uuid"), ...skillCreate },
  SKILL_DELETE: { skillId: required("uuid") },
  EXPERIENCE_SKILL_LINK: { experienceId: required("uuid"), skillId: required("uuid") },
  EXPERIENCE_SKILL_UNLINK: { experienceId: required("uuid"), skillId: required("uuid") },
  GOAL_CREATE: goalCreate,
  GOAL_UPDATE: { goalId: required("uuid"), ...goalCreate },
  GOAL_DELETE: { goalId: required("uuid") },
  PREFERENCE_CREATE: preferenceCreate,
  PREFERENCE_UPDATE: { preferenceId: required("uuid"), ...preferenceCreate },
  PREFERENCE_DELETE: { preferenceId: required("uuid") },
});

export const PROFILE_COMMANDS = Object.freeze(Object.keys(PROFILE_COMMAND_SCHEMAS) as ProfileCommand[]);
export const PROFILE_COMMAND_KEY_CONTRACT = Object.freeze(Object.fromEntries(
  PROFILE_COMMANDS.map((command) => {
    const schema = PROFILE_COMMAND_SCHEMAS[command];
    return [command, Object.freeze({
      allowed: Object.freeze(Object.keys(schema)),
      required: Object.freeze(Object.entries(schema).filter(([, rule]) => rule.required).map(([key]) => key)),
    })];
  }),
) as Record<ProfileCommand, Readonly<{ allowed: readonly string[]; required: readonly string[] }>>);

export class ProfileContractError extends Error {
  constructor() {
    super("INVALID_REQUEST");
    this.name = "ProfileContractError";
  }
}

function invalid(): never {
  throw new ProfileContractError();
}

function objectValue(value: unknown): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) invalid();
  return value as Record<string, unknown>;
}

function closedObject(value: unknown, allowed: readonly string[], requiredKeys: readonly string[] = allowed): Record<string, unknown> {
  const object = objectValue(value);
  if (Object.keys(object).some((key) => !allowed.includes(key))) invalid();
  if (requiredKeys.some((key) => !(key in object) || object[key] === null)) invalid();
  return object;
}

function closedResponseObject(value: unknown, keys: readonly string[]): Record<string, unknown> {
  const object = closedObject(value, keys, []);
  if (keys.some((key) => !(key in object))) invalid();
  return object;
}

function uuid(value: unknown): string {
  if (typeof value !== "string" || !PROFILE_UUID_PATTERN.test(value)) invalid();
  return value.toLowerCase();
}

function textValue(value: unknown): string {
  if (typeof value !== "string") invalid();
  return value;
}

function finiteNumber(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value)) invalid();
  return value;
}

function integer(value: unknown): number {
  const result = finiteNumber(value);
  if (!Number.isSafeInteger(result)) invalid();
  return result;
}

function nonNegativeInteger(value: unknown): number {
  const result = integer(value);
  if (result < 0) invalid();
  return result;
}

function enumValue(value: unknown, values: readonly string[]): string {
  if (typeof value !== "string" || !values.includes(value)) invalid();
  return value;
}

function dateValue(value: unknown): string {
  const result = textValue(value);
  if (!DATE_PATTERN.test(result) || Number.isNaN(Date.parse(`${result}T00:00:00Z`))) invalid();
  return result;
}

function timestampValue(value: unknown): string {
  const result = textValue(value);
  if (Number.isNaN(Date.parse(result))) invalid();
  return result;
}

function hashValue(value: unknown): string {
  const result = textValue(value).toLowerCase();
  if (!SHA256_PATTERN.test(result)) invalid();
  return result;
}

function sectionScores(value: unknown): Readonly<Record<string, number>> {
  const object = objectValue(value);
  const result: Record<string, number> = {};
  for (const [key, score] of Object.entries(object)) {
    if (!(PROFILE_SECTION_SCORE_KEYS as readonly string[]).includes(key)) invalid();
    const parsed = finiteNumber(score);
    if (parsed < 0) invalid();
    result[key] = parsed;
  }
  return Object.freeze(result);
}

function preferenceValue(value: unknown, preferenceType: unknown): ProfilePreferenceValue {
  const type = enumValue(preferenceType, PROFILE_PREFERENCE_TYPES);
  if (type === "LOCATION") {
    const object = closedObject(value, ["countryCodes"]);
    if (!Array.isArray(object.countryCodes) || object.countryCodes.length === 0) invalid();
    const countryCodes = object.countryCodes.map((entry) => {
      if (typeof entry !== "string" || !/^[A-Z]{2}$/.test(entry)) invalid();
      return entry;
    });
    return Object.freeze({ countryCodes: Object.freeze(countryCodes) });
  }
  if (type === "DELIVERY_MODE") {
    const object = closedObject(value, ["modes"]);
    const modes = ["IN_PERSON", "ONLINE", "HYBRID"] as const;
    if (!Array.isArray(object.modes) || object.modes.length === 0) invalid();
    return Object.freeze({ modes: Object.freeze(object.modes.map((entry) => enumValue(entry, modes) as (typeof modes)[number])) });
  }
  if (type === "BUDGET") {
    const object = closedObject(value, ["currencyCode", "maximumAmount"]);
    const currencyCode = textValue(object.currencyCode);
    const maximumAmount = finiteNumber(object.maximumAmount);
    if (!/^[A-Z]{3}$/.test(currencyCode) || maximumAmount < 0) invalid();
    return Object.freeze({ currencyCode, maximumAmount });
  }
  const object = closedObject(value, ["minimumMonths", "maximumMonths"], []);
  if (!("minimumMonths" in object) && !("maximumMonths" in object)) invalid();
  const minimumMonths = object.minimumMonths === undefined ? undefined : finiteNumber(object.minimumMonths);
  const maximumMonths = object.maximumMonths === undefined ? undefined : finiteNumber(object.maximumMonths);
  if ((minimumMonths ?? 1) <= 0 || (maximumMonths ?? 1) <= 0) invalid();
  if (minimumMonths !== undefined && maximumMonths !== undefined && maximumMonths < minimumMonths) invalid();
  return Object.freeze({ ...(minimumMonths === undefined ? {} : { minimumMonths }), ...(maximumMonths === undefined ? {} : { maximumMonths }) });
}

function parseField(value: unknown, rule: FieldRule, object: Record<string, unknown>): unknown {
  if (value === null) {
    if (rule.nullable) return null;
    invalid();
  }
  switch (rule.kind) {
    case "uuid": return uuid(value);
    case "string": return textValue(value);
    case "number": return finiteNumber(value);
    case "integer": return integer(value);
    case "date": return dateValue(value);
    case "timestamp": return timestampValue(value);
    case "hash": return hashValue(value);
    case "enum": return enumValue(value, rule.values ?? []);
    case "sectionScores": return sectionScores(value);
    case "preferenceValue": return preferenceValue(value, object.preferenceType);
  }
}

export function parseProfileMutationCommand(value: unknown): ProfileMutationCommand {
  const envelope = closedObject(value, ["command", "payload"]);
  if (typeof envelope.command !== "string" || !(envelope.command in PROFILE_COMMAND_SCHEMAS)) invalid();
  const command = envelope.command as ProfileCommand;
  const schema = PROFILE_COMMAND_SCHEMAS[command];
  const contract = PROFILE_COMMAND_KEY_CONTRACT[command];
  const payload = closedObject(envelope.payload, contract.allowed, contract.required);
  const normalized: Record<string, unknown> = {};
  for (const key of contract.allowed) {
    if (!(key in payload)) continue;
    normalized[key] = parseField(payload[key], schema[key], payload);
  }

  if (command === "COMPLETENESS_UPSERT") {
    if (normalized.completeness === "COMPLETE") normalized.explanation = null;
    else if (typeof normalized.explanation !== "string" || normalized.explanation.trim() === "") invalid();
  }
  if (command.startsWith("DEGREE_")) {
    const gpaValue = normalized.gpaValue;
    const gpaScale = normalized.gpaScale;
    if ((gpaValue == null) !== (gpaScale == null)) invalid();
    if (typeof gpaValue === "number" && typeof gpaScale === "number" && (gpaScale <= 0 || gpaValue < 0 || gpaValue > gpaScale)) invalid();
    if (typeof normalized.countryCode === "string" && !/^[A-Z]{2}$/.test(normalized.countryCode)) invalid();
  }
  if (command.startsWith("COURSE_")) {
    const gradeValue = normalized.gradeValue;
    const gradeScale = normalized.gradeScale;
    if ((gradeValue == null) !== (gradeScale == null)) invalid();
    if (typeof normalized.credits === "number" && normalized.credits <= 0) invalid();
    if (typeof gradeValue === "number" && typeof gradeScale === "number" && (gradeScale <= 0 || gradeValue < 0 || gradeValue > gradeScale)) invalid();
  }
  if (command === "TEST_SCORE_CREATE" || command === "TEST_SCORE_UPDATE") {
    const scores = normalized.sectionScores;
    if (normalized.totalScore == null && (scores == null || Object.keys(scores as object).length === 0)) invalid();
  }
  if (command.startsWith("EXPERIENCE_")) {
    if (typeof normalized.hoursPerWeek === "number" && (normalized.hoursPerWeek < 0 || normalized.hoursPerWeek > 168)) invalid();
  }
  if (command.startsWith("SKILL_")) {
    if (typeof normalized.proficiencyLevel === "number" && (normalized.proficiencyLevel < 1 || normalized.proficiencyLevel > 5)) invalid();
    if (typeof normalized.yearsExperience === "number" && normalized.yearsExperience < 0) invalid();
  }
  if (command.startsWith("GOAL_")) {
    if (typeof normalized.priority === "number" && (normalized.priority < 1 || normalized.priority > 5)) invalid();
    if (command !== "GOAL_DELETE" && normalized.conceptId == null && (typeof normalized.goalText !== "string" || normalized.goalText.trim() === "")) invalid();
  }
  if (command.startsWith("PREFERENCE_") && command !== "PREFERENCE_DELETE") {
    if (typeof normalized.priority !== "number" || normalized.priority < 1 || normalized.priority > 5) invalid();
  }
  return Object.freeze({ command, payload: Object.freeze(normalized) }) as ProfileMutationCommand;
}

export type ProfileReadiness = Readonly<{
  schemaVersion: "PROFILE_READINESS_V019";
  freezeReady: boolean;
  requiredScopeCount: number;
  declaredRequiredScopeCount: number;
  missingDeclarations: readonly Readonly<{ educationContextId: string | null; domain: DataDomain }>[];
  declarations: readonly Readonly<{ completenessId: string; educationContextId: string | null; domain: DataDomain; completeness: Completeness; explanation: string | null }>[];
  mappingReadiness: readonly Readonly<{ recordType: "DEGREE" | "COURSE"; recordId: string; verified: boolean; mappingStatuses: readonly MappingStatus[] }>[];
}>;

export type ProfileDocument = Readonly<{
  schemaVersion: "PROFILE_DOCUMENT_V019";
  profileVersionId: string;
  versionNumber: number;
  status: "DRAFT" | "FROZEN";
  revision: number;
  snapshotHash: string | null;
  frozenAt: string | null;
  readiness: ProfileReadiness;
  evidenceItems: readonly Record<string, unknown>[];
  degrees: readonly Record<string, unknown>[];
  courses: readonly Record<string, unknown>[];
  testScores: readonly Record<string, unknown>[];
  experiences: readonly Record<string, unknown>[];
  skills: readonly Record<string, unknown>[];
  experienceSkills: readonly Record<string, unknown>[];
  goals: readonly Record<string, unknown>[];
  preferences: readonly Record<string, unknown>[];
  mappings: readonly Record<string, unknown>[];
}>;

export type ProfileAccount = Readonly<{ schemaVersion: "PROFILE_ACCOUNT_V019"; accountState: "ACTIVE"; hasCurrentDraft: boolean }>;
export type ProfileOperationResult = Readonly<Record<string, unknown> & { schemaVersion: "PROFILE_OPERATION_RESULT_V019" | "PROFILE_OPERATION_RESULT_V020"; operation: "CREATE_OR_RESUME" | "MUTATE" | "FREEZE" | "FORK_FROZEN"; profileVersionId: string; revision: number }>;

type ClosedField = Readonly<{ key: string; kind: "boolean" | "enum" | "integer" | "nullableHash" | "nullableInteger" | "nullableNumber" | "nullableString" | "nullableUuid" | "number" | "object" | "string" | "uuid"; values?: readonly string[] }>;

function parseClosedRecord(value: unknown, fields: readonly ClosedField[]): Readonly<Record<string, unknown>> {
  const object = closedResponseObject(value, fields.map((field) => field.key));
  const result: Record<string, unknown> = {};
  for (const field of fields) {
    const entry = object[field.key];
    switch (field.kind) {
      case "uuid": result[field.key] = uuid(entry); break;
      case "string": result[field.key] = textValue(entry); break;
      case "nullableString": result[field.key] = entry === null ? null : textValue(entry); break;
      case "nullableUuid": result[field.key] = entry === null ? null : uuid(entry); break;
      case "number": result[field.key] = finiteNumber(entry); break;
      case "nullableNumber": result[field.key] = entry === null ? null : finiteNumber(entry); break;
      case "integer": result[field.key] = integer(entry); break;
      case "nullableInteger": result[field.key] = entry === null ? null : integer(entry); break;
      case "boolean": if (typeof entry !== "boolean") invalid(); else result[field.key] = entry; break;
      case "enum": result[field.key] = enumValue(entry, field.values ?? []); break;
      case "nullableHash": result[field.key] = entry === null ? null : hashValue(entry); break;
      case "object": result[field.key] = objectValue(entry); break;
    }
  }
  return Object.freeze(result);
}

function parseClosedArray(value: unknown, fields: readonly ClosedField[]): readonly Readonly<Record<string, unknown>>[] {
  if (!Array.isArray(value)) invalid();
  return Object.freeze(value.map((entry) => parseClosedRecord(entry, fields)));
}

export function parseProfileReadiness(value: unknown): ProfileReadiness {
  const object = closedObject(value, ["schemaVersion", "freezeReady", "requiredScopeCount", "declaredRequiredScopeCount", "missingDeclarations", "declarations", "mappingReadiness"]);
  if (object.schemaVersion !== "PROFILE_READINESS_V019" || typeof object.freezeReady !== "boolean") invalid();
  const requiredScopeCount = integer(object.requiredScopeCount);
  const declaredRequiredScopeCount = integer(object.declaredRequiredScopeCount);
  if (requiredScopeCount < 0 || declaredRequiredScopeCount < 0 || declaredRequiredScopeCount > requiredScopeCount) invalid();
  const missingDeclarations = parseClosedArray(object.missingDeclarations, [
    { key: "educationContextId", kind: "nullableString" },
    { key: "domain", kind: "enum", values: PROFILE_DATA_DOMAINS },
  ]).map((entry) => ({ ...entry, educationContextId: entry.educationContextId === null ? null : uuid(entry.educationContextId) }));
  const declarations = parseClosedArray(object.declarations, [
    { key: "completenessId", kind: "uuid" }, { key: "educationContextId", kind: "nullableString" },
    { key: "domain", kind: "enum", values: PROFILE_DATA_DOMAINS }, { key: "completeness", kind: "enum", values: PROFILE_COMPLETENESS_VALUES },
    { key: "explanation", kind: "nullableString" },
  ]).map((entry) => ({ ...entry, educationContextId: entry.educationContextId === null ? null : uuid(entry.educationContextId) }));
  if (!Array.isArray(object.mappingReadiness)) invalid();
  const mappingReadiness = object.mappingReadiness.map((entry) => {
    const mapping = closedObject(entry, ["recordType", "recordId", "verified", "mappingStatuses"]);
    if (typeof mapping.verified !== "boolean" || !Array.isArray(mapping.mappingStatuses)) invalid();
    return Object.freeze({
      recordType: enumValue(mapping.recordType, ["DEGREE", "COURSE"]) as "DEGREE" | "COURSE",
      recordId: uuid(mapping.recordId),
      verified: mapping.verified,
      mappingStatuses: Object.freeze(mapping.mappingStatuses.map((status) => enumValue(status, PROFILE_MAPPING_STATUSES) as MappingStatus)),
    });
  });
  return Object.freeze({
    schemaVersion: "PROFILE_READINESS_V019", freezeReady: object.freezeReady,
    requiredScopeCount, declaredRequiredScopeCount,
    missingDeclarations: Object.freeze(missingDeclarations) as ProfileReadiness["missingDeclarations"],
    declarations: Object.freeze(declarations) as ProfileReadiness["declarations"],
    mappingReadiness: Object.freeze(mappingReadiness),
  });
}

const documentArrayFields = {
  evidenceItems: [
    { key: "evidenceId", kind: "uuid" }, { key: "evidenceType", kind: "enum", values: PROFILE_EVIDENCE_TYPES },
    { key: "locator", kind: "nullableString" }, { key: "contentHash", kind: "nullableHash" }, { key: "observedAt", kind: "string" },
  ],
  degrees: [
    { key: "degreeId", kind: "uuid" }, { key: "institutionName", kind: "string" }, { key: "degreeName", kind: "string" },
    { key: "degreeLevel", kind: "enum", values: PROFILE_DEGREE_LEVELS }, { key: "degreeStatus", kind: "enum", values: PROFILE_DEGREE_STATUSES },
    { key: "startDate", kind: "nullableString" }, { key: "completionDate", kind: "nullableString" }, { key: "countryCode", kind: "nullableString" },
    { key: "gpaValue", kind: "nullableNumber" }, { key: "gpaScale", kind: "nullableNumber" }, { key: "evidenceId", kind: "uuid" },
  ],
  courses: [
    { key: "courseId", kind: "uuid" }, { key: "degreeId", kind: "nullableUuid" }, { key: "courseCode", kind: "nullableString" },
    { key: "courseTitle", kind: "string" }, { key: "courseStatus", kind: "enum", values: PROFILE_COURSE_STATUSES },
    { key: "term", kind: "nullableString" }, { key: "completionDate", kind: "nullableString" }, { key: "credits", kind: "nullableNumber" },
    { key: "gradeValue", kind: "nullableNumber" }, { key: "gradeScale", kind: "nullableNumber" }, { key: "gradeText", kind: "nullableString" },
    { key: "evidenceId", kind: "uuid" },
  ],
  testScores: [
    { key: "testScoreId", kind: "uuid" }, { key: "assessmentConceptId", kind: "uuid" }, { key: "testDate", kind: "string" },
    { key: "totalScore", kind: "nullableNumber" }, { key: "sectionScores", kind: "object" }, { key: "evidenceId", kind: "uuid" },
  ],
  experiences: [
    { key: "experienceId", kind: "uuid" }, { key: "experienceType", kind: "enum", values: PROFILE_EXPERIENCE_TYPES },
    { key: "organizationName", kind: "nullableString" }, { key: "roleTitle", kind: "string" }, { key: "startDate", kind: "nullableString" },
    { key: "endDate", kind: "nullableString" }, { key: "hoursPerWeek", kind: "nullableNumber" }, { key: "description", kind: "nullableString" },
    { key: "evidenceId", kind: "uuid" },
  ],
  skills: [
    { key: "skillId", kind: "uuid" }, { key: "skillConceptId", kind: "uuid" }, { key: "proficiencyLevel", kind: "nullableInteger" },
    { key: "yearsExperience", kind: "nullableNumber" }, { key: "evidenceId", kind: "uuid" },
  ],
  experienceSkills: [{ key: "experienceId", kind: "uuid" }, { key: "skillId", kind: "uuid" }],
  goals: [
    { key: "goalId", kind: "uuid" }, { key: "goalType", kind: "enum", values: PROFILE_GOAL_TYPES }, { key: "conceptId", kind: "nullableUuid" },
    { key: "goalText", kind: "nullableString" }, { key: "priority", kind: "integer" },
  ],
  preferences: [
    { key: "preferenceId", kind: "uuid" }, { key: "preferenceType", kind: "string" }, { key: "value", kind: "object" }, { key: "priority", kind: "integer" },
  ],
  mappings: [
    { key: "mappingId", kind: "uuid" }, { key: "recordType", kind: "enum", values: ["DEGREE", "COURSE"] }, { key: "recordId", kind: "uuid" },
    { key: "conceptId", kind: "uuid" }, { key: "mappingStatus", kind: "enum", values: PROFILE_MAPPING_STATUSES }, { key: "evidenceId", kind: "nullableUuid" },
  ],
} as const satisfies Record<string, readonly ClosedField[]>;

export function parseProfileDocument(value: unknown): ProfileDocument {
  const keys = ["schemaVersion", "profileVersionId", "versionNumber", "status", "revision", "snapshotHash", "frozenAt", "readiness", ...Object.keys(documentArrayFields)];
  const object = closedResponseObject(value, keys);
  if (object.schemaVersion !== "PROFILE_DOCUMENT_V019") invalid();
  const status = enumValue(object.status, ["DRAFT", "FROZEN"]) as "DRAFT" | "FROZEN";
  const snapshotHash = object.snapshotHash === null ? null : hashValue(object.snapshotHash);
  const frozenAt = object.frozenAt === null ? null : timestampValue(object.frozenAt);
  if ((status === "DRAFT" && (snapshotHash !== null || frozenAt !== null)) || (status === "FROZEN" && (snapshotHash === null || frozenAt === null))) invalid();
  const arrays = Object.fromEntries(Object.entries(documentArrayFields).map(([key, fields]) => [key, parseClosedArray(object[key], fields)]));
  const versionNumber = nonNegativeInteger(object.versionNumber);
  const revision = nonNegativeInteger(object.revision);
  if (versionNumber < 1) invalid();
  return Object.freeze({
    schemaVersion: "PROFILE_DOCUMENT_V019", profileVersionId: uuid(object.profileVersionId), versionNumber,
    status, revision, snapshotHash, frozenAt, readiness: parseProfileReadiness(object.readiness),
    ...arrays,
  }) as ProfileDocument;
}

export function parseProfileAccount(value: unknown): ProfileAccount {
  const object = closedObject(value, ["schemaVersion", "accountState", "hasCurrentDraft"]);
  if (object.schemaVersion !== "PROFILE_ACCOUNT_V019" || object.accountState !== "ACTIVE" || typeof object.hasCurrentDraft !== "boolean") invalid();
  return Object.freeze({ schemaVersion: "PROFILE_ACCOUNT_V019", accountState: "ACTIVE", hasCurrentDraft: object.hasCurrentDraft });
}

export function parseProfileOperationResult(value: unknown): ProfileOperationResult {
  const object = objectValue(value);
  const schemaVersion = enumValue(object.schemaVersion, ["PROFILE_OPERATION_RESULT_V019", "PROFILE_OPERATION_RESULT_V020"]) as ProfileOperationResult["schemaVersion"];
  const operation = enumValue(object.operation, ["CREATE_OR_RESUME", "MUTATE", "FREEZE", "FORK_FROZEN"]) as ProfileOperationResult["operation"];
  const allowedByOperation: Record<ProfileOperationResult["operation"], readonly string[]> = {
    CREATE_OR_RESUME: ["schemaVersion", "operation", "profileVersionId", "versionNumber", "status", "revision"],
    MUTATE: ["schemaVersion", "operation", "command", "profileVersionId", "revision", "resourceId", "resourceKey"],
    FREEZE: ["schemaVersion", "operation", "profileVersionId", "status", "revision", "document"],
    FORK_FROZEN: ["schemaVersion", "operation", "sourceProfileVersionId", "profileVersionId", "versionNumber", "status", "revision"],
  };
  closedResponseObject(object, allowedByOperation[operation]);
  if (
    (operation === "FORK_FROZEN" && schemaVersion !== "PROFILE_OPERATION_RESULT_V020") ||
    (operation !== "FORK_FROZEN" && schemaVersion !== "PROFILE_OPERATION_RESULT_V019")
  ) invalid();
  const result: Record<string, unknown> = { ...object, schemaVersion, operation, profileVersionId: uuid(object.profileVersionId), revision: nonNegativeInteger(object.revision) };
  if ("versionNumber" in object) {
    const versionNumber = nonNegativeInteger(object.versionNumber);
    if (versionNumber < 1) invalid();
    result.versionNumber = versionNumber;
  }
  if ("sourceProfileVersionId" in object) result.sourceProfileVersionId = uuid(object.sourceProfileVersionId);
  if (operation === "CREATE_OR_RESUME" || operation === "FORK_FROZEN") {
    if (object.status !== "DRAFT") invalid();
    result.status = "DRAFT";
  }
  if (operation === "MUTATE") {
    result.command = enumValue(object.command, PROFILE_COMMANDS);
    result.resourceId = object.resourceId === null ? null : uuid(object.resourceId);
    if (result.command === "EXPERIENCE_SKILL_LINK" || result.command === "EXPERIENCE_SKILL_UNLINK") {
      const resourceKey = closedObject(object.resourceKey, ["experienceId", "skillId"]);
      result.resourceKey = Object.freeze({ experienceId: uuid(resourceKey.experienceId), skillId: uuid(resourceKey.skillId) });
      if (result.resourceId !== null) invalid();
    } else {
      if (object.resourceKey !== null) invalid();
      result.resourceKey = null;
    }
  }
  if (operation === "FREEZE") {
    if (object.status !== "FROZEN") invalid();
    const document = parseProfileDocument(object.document);
    if (
      document.status !== "FROZEN" ||
      document.profileVersionId !== result.profileVersionId ||
      document.revision !== result.revision
    ) invalid();
    result.status = "FROZEN";
    result.document = document;
  }
  return Object.freeze(result) as ProfileOperationResult;
}

export function parseEmptyRequest(value: unknown): Readonly<Record<string, never>> {
  closedObject(value, [], []);
  return Object.freeze({});
}

export function parseCreateDraftRequest(value: unknown): Readonly<{ operationId: string }> {
  const object = closedObject(value, ["operationId"]);
  return Object.freeze({ operationId: uuid(object.operationId) });
}

export function parseProfileIdRequest(value: unknown): Readonly<{ profileVersionId: string }> {
  const object = closedObject(value, ["profileVersionId"]);
  return Object.freeze({ profileVersionId: uuid(object.profileVersionId) });
}

export function parseRevisionRequest(value: unknown): Readonly<{ profileVersionId: string; operationId: string; expectedRevision: number }> {
  const object = closedObject(value, ["profileVersionId", "operationId", "expectedRevision"]);
  const expectedRevision = integer(object.expectedRevision);
  if (expectedRevision < 0) invalid();
  return Object.freeze({ profileVersionId: uuid(object.profileVersionId), operationId: uuid(object.operationId), expectedRevision });
}

export function parseForkRequest(value: unknown): Readonly<{ sourceProfileVersionId: string; operationId: string }> {
  const object = closedObject(value, ["sourceProfileVersionId", "operationId"]);
  return Object.freeze({ sourceProfileVersionId: uuid(object.sourceProfileVersionId), operationId: uuid(object.operationId) });
}

export function parseMutationRequest(value: unknown): Readonly<{ profileVersionId: string; operationId: string; expectedRevision: number } & ProfileMutationCommand> {
  const object = closedObject(value, ["profileVersionId", "operationId", "expectedRevision", "command", "payload"]);
  const expectedRevision = integer(object.expectedRevision);
  if (expectedRevision < 0) invalid();
  const mutation = parseProfileMutationCommand({ command: object.command, payload: object.payload });
  return Object.freeze({ profileVersionId: uuid(object.profileVersionId), operationId: uuid(object.operationId), expectedRevision, ...mutation });
}
