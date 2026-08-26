export const FIT_INTENT_DIMENSIONS = [
  "ACADEMIC",
  "CAREER",
  "FINANCIAL",
  "GEOGRAPHIC_DELIVERY",
  "PERSONAL_PREFERENCE",
  "INTERNATIONAL_ACCESSIBILITY",
] as const;

export const FIT_INTENT_DIMENSION_STATES = [
  "UNANSWERED",
  "DECLARED",
  "EXPLICIT_NOT_SUPPLIED",
] as const;

export const FIT_INTENT_IMPORTANCE = [
  "REQUIRED",
  "STRONGLY_PREFERRED",
  "PREFERRED",
  "NEUTRAL",
  "UNSPECIFIED",
] as const;

export const FIT_INTENT_COMMANDS = [
  "DECLARATION_CREATE",
  "DECLARATION_REPLACE",
  "DECLARATION_DELETE",
  "DIMENSION_MARK_NOT_SUPPLIED",
  "ACCESS_CONTEXT_REPLACE",
  "ACCESS_CONTEXT_DELETE",
] as const;

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SHA256_PATTERN = /^[a-f0-9]{64}$/;
const RELEASE_PATTERN = /^[A-Za-z0-9._-]{1,64}$/;
const MAX_DECLARATIONS = 64;
const MAX_OPTIONS = 64;

export type FitIntentDimension = (typeof FIT_INTENT_DIMENSIONS)[number];
export type FitIntentDimensionState = (typeof FIT_INTENT_DIMENSION_STATES)[number];
export type FitIntentImportance = (typeof FIT_INTENT_IMPORTANCE)[number];
export type FitIntentCommand = (typeof FIT_INTENT_COMMANDS)[number];

export type FitIntentTypedValue =
  | Readonly<{ conceptId: string; relation: "DESIRED" | "EXCLUDED" }>
  | Readonly<{ deliveryMode: "IN_PERSON" | "ONLINE" | "HYBRID"; relation: "DESIRED" | "EXCLUDED" }>
  | Readonly<{
      amount: number;
      constraintSemantics: "HARD_TOTAL_COST_CEILING" | "PREFERRED_TOTAL_COST" | "HARD_TUITION_CEILING" | "PREFERRED_TUITION";
      currency: string;
      scope: "COMPONENT" | "TOTAL_COST";
      period: "MONTH" | "ACADEMIC_YEAR" | "CALENDAR_YEAR" | "PROGRAM_DURATION" | "ACADEMIC_SEMESTER" | "CREDIT";
      basis: "GROSS";
      components: readonly ("TUITION" | "TOTAL_COST")[];
    }>
  | Readonly<{ minimumMonths: number | null; maximumMonths: number | null }>
  | Readonly<{ featureKey: "CAPSTONE_AVAILABLE"; expected: boolean }>;

export type FitIntentDeclarationInput = Readonly<{
  dimension: FitIntentDimension;
  semanticType: "TAXONOMY_TARGET" | "DELIVERY_CONSTRAINT" | "FINANCIAL_CONSTRAINT" | "DURATION_CONSTRAINT" | "PROGRAM_FEATURE_CONSTRAINT";
  importance: FitIntentImportance;
  importanceConfirmedByStudent: boolean;
  typedValue: FitIntentTypedValue;
}>;

export type FitIntentMutation =
  | Readonly<{ command: "DECLARATION_CREATE"; payload: Readonly<{ declaration: FitIntentDeclarationInput }> }>
  | Readonly<{ command: "DECLARATION_REPLACE"; payload: Readonly<{ declarationId: string; declaration: FitIntentDeclarationInput }> }>
  | Readonly<{ command: "DECLARATION_DELETE"; payload: Readonly<{ declarationId: string }> }>
  | Readonly<{ command: "DIMENSION_MARK_NOT_SUPPLIED"; payload: Readonly<{ dimension: FitIntentDimension }> }>
  | Readonly<{
      command: "ACCESS_CONTEXT_REPLACE";
      payload: Readonly<{
        citizenshipCountryCode?: string | null;
        residenceCountryCode?: string | null;
        jurisdictionCode: string;
        currentStatusCode?: string | null;
        authorizationPathCode?: string | null;
        targetPathCode: string;
      }>;
    }>
  | Readonly<{ command: "ACCESS_CONTEXT_DELETE"; payload: Readonly<Record<never, never>> }>;

export type FitIntentDocument = Readonly<{
  schemaVersion: "FIT_INTENT_DOCUMENT_V027";
  intentSetId: string;
  profileVersionId: string;
  versionNumber: number;
  status: "DRAFT" | "FROZEN";
  revision: number;
  snapshotHash: string | null;
  taxonomyRelease: Readonly<{ releaseCode: string; releaseOrdinal: number }>;
  dimensions: readonly Readonly<{ dimension: FitIntentDimension; state: FitIntentDimensionState }>[];
  declarations: readonly Readonly<{
    declarationId: string;
    dimension: FitIntentDimension;
    semanticType: FitIntentDeclarationInput["semanticType"];
    importance: FitIntentImportance;
    importanceConfirmedByStudent: boolean;
    provenance: "SELF_ASSERTED";
    typedValue: FitIntentTypedValue;
  }>[];
  accessContext: Readonly<{
    accessContextId: string;
    citizenshipCountryCode: string | null;
    residenceCountryCode: string | null;
    jurisdictionCode: string;
    currentStatusCode: string | null;
    authorizationPathCode: string | null;
    targetPathCode: string;
    provenance: "SELF_ASSERTED";
  }> | null;
  readiness: Readonly<{
    freezeReady: boolean;
    issues: readonly Readonly<{ code: "DIMENSION_UNANSWERED"; dimension: FitIntentDimension }>[];
  }>;
}>;

export type FitIntentOperationResult = Readonly<{
  schemaVersion: "FIT_INTENT_OPERATION_RESULT_V027";
  operation: "CREATE_OR_RESUME" | "MUTATE" | "FREEZE";
  intentSetId: string;
  profileVersionId?: string;
  versionNumber?: number;
  status?: "DRAFT" | "FROZEN";
  revision: number;
  command?: FitIntentCommand;
  resourceId?: string | null;
  snapshotHash?: string;
  document?: FitIntentDocument;
}>;

export type FitIntentDiscovery = Readonly<{
  schemaVersion: "FIT_INTENT_DISCOVERY_V027";
  profileVersionId: string;
  activeDraft: FitIntentDocument | null;
  latestFrozen: FitIntentDocument | null;
}>;

export type FitIntentTaxonomyOptions = Readonly<{
  schemaVersion: "FIT_INTENT_TAXONOMY_OPTIONS_V027";
  intentSetId: string;
  dimension: "ACADEMIC" | "CAREER" | "INTERNATIONAL_ACCESSIBILITY";
  releaseCode: string;
  releaseOrdinal: number;
  options: readonly Readonly<{
    conceptId: string;
    conceptKind: string;
    canonicalKey: string;
    displayName: string;
  }>[];
}>;

export type FitAccessContextOptions = Readonly<{
  schemaVersion: "FIT_ACCESS_CONTEXT_OPTIONS_V027";
  intentSetId: string;
  options: readonly Readonly<{ jurisdictionCode: string; targetPathCode: string }>[];
}>;

export class FitIntentContractError extends Error {
  constructor() {
    super("INVALID_REQUEST");
    this.name = "FitIntentContractError";
  }
}

function invalid(): never {
  throw new FitIntentContractError();
}

function object(value: unknown): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) invalid();
  return value as Record<string, unknown>;
}

function exact(value: unknown, allowed: readonly string[], required: readonly string[] = allowed): Record<string, unknown> {
  const result = object(value);
  if (Object.keys(result).some((key) => !allowed.includes(key))) invalid();
  if (required.some((key) => !(key in result))) invalid();
  return result;
}

function uuid(value: unknown): string {
  if (typeof value !== "string" || !UUID_PATTERN.test(value)) invalid();
  return value.toLowerCase();
}

function text(value: unknown, maximum = 256): string {
  if (typeof value !== "string" || value.length === 0 || new TextEncoder().encode(value).length > maximum) invalid();
  return value;
}

function nullableText(value: unknown, maximum = 256): string | null {
  return value === null ? null : text(value, maximum);
}

function integer(value: unknown, minimum = 0): number {
  if (!Number.isSafeInteger(value) || (value as number) < minimum) invalid();
  return value as number;
}

function number(value: unknown, minimum = 0): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < minimum) invalid();
  return value;
}

function enumValue<T extends readonly string[]>(value: unknown, values: T): T[number] {
  if (typeof value !== "string" || !(values as readonly unknown[]).includes(value)) invalid();
  return value as T[number];
}

function hash(value: unknown): string {
  if (typeof value !== "string" || !SHA256_PATTERN.test(value)) invalid();
  return value;
}

function parseTypedValue(semanticType: FitIntentDeclarationInput["semanticType"], dimension: FitIntentDimension, value: unknown): FitIntentTypedValue {
  if (semanticType === "TAXONOMY_TARGET") {
    if (!["ACADEMIC", "CAREER", "INTERNATIONAL_ACCESSIBILITY"].includes(dimension)) invalid();
    const row = exact(value, ["conceptId", "relation"]);
    return Object.freeze({ conceptId: uuid(row.conceptId), relation: enumValue(row.relation, ["DESIRED", "EXCLUDED"] as const) });
  }
  if (semanticType === "DELIVERY_CONSTRAINT") {
    if (dimension !== "GEOGRAPHIC_DELIVERY") invalid();
    const row = exact(value, ["deliveryMode", "relation"]);
    return Object.freeze({
      deliveryMode: enumValue(row.deliveryMode, ["IN_PERSON", "ONLINE", "HYBRID"] as const),
      relation: enumValue(row.relation, ["DESIRED", "EXCLUDED"] as const),
    });
  }
  if (semanticType === "FINANCIAL_CONSTRAINT") {
    if (dimension !== "FINANCIAL") invalid();
    const row = exact(value, ["amount", "constraintSemantics", "currency", "scope", "period", "basis", "components"]);
    if (!Array.isArray(row.components) || row.components.length !== 1) invalid();
    const constraintSemantics = enumValue(row.constraintSemantics, [
      "HARD_TOTAL_COST_CEILING", "PREFERRED_TOTAL_COST", "HARD_TUITION_CEILING", "PREFERRED_TUITION",
    ] as const);
    const scope = enumValue(row.scope, ["COMPONENT", "TOTAL_COST"] as const);
    const components = Object.freeze(row.components.map((entry) => enumValue(entry, ["TUITION", "TOTAL_COST"] as const)));
    if ((scope === "TOTAL_COST" && components[0] !== "TOTAL_COST") || (scope === "COMPONENT" && components[0] !== "TUITION")) invalid();
    const currency = text(row.currency, 3).toUpperCase();
    if (!/^[A-Z]{3}$/.test(currency)) invalid();
    return Object.freeze({
      amount: number(row.amount),
      constraintSemantics,
      currency,
      scope,
      period: enumValue(row.period, ["MONTH", "ACADEMIC_YEAR", "CALENDAR_YEAR", "PROGRAM_DURATION", "ACADEMIC_SEMESTER", "CREDIT"] as const),
      basis: enumValue(row.basis, ["GROSS"] as const),
      components,
    });
  }
  if (semanticType === "DURATION_CONSTRAINT") {
    if (dimension !== "PERSONAL_PREFERENCE") invalid();
    const row = exact(value, ["minimumMonths", "maximumMonths"]);
    const minimumMonths = row.minimumMonths === null ? null : number(row.minimumMonths, 0.01);
    const maximumMonths = row.maximumMonths === null ? null : number(row.maximumMonths, 0.01);
    if (minimumMonths === null && maximumMonths === null) invalid();
    if (minimumMonths !== null && maximumMonths !== null && maximumMonths < minimumMonths) invalid();
    return Object.freeze({ minimumMonths, maximumMonths });
  }
  if (dimension !== "PERSONAL_PREFERENCE") invalid();
  const row = exact(value, ["featureKey", "expected"]);
  if (row.featureKey !== "CAPSTONE_AVAILABLE" || typeof row.expected !== "boolean") invalid();
  return Object.freeze({ featureKey: "CAPSTONE_AVAILABLE", expected: row.expected });
}

function parseDeclaration(value: unknown): FitIntentDeclarationInput {
  const row = exact(value, ["dimension", "semanticType", "importance", "importanceConfirmedByStudent", "typedValue"]);
  const dimension = enumValue(row.dimension, FIT_INTENT_DIMENSIONS);
  const semanticType = enumValue(row.semanticType, [
    "TAXONOMY_TARGET", "DELIVERY_CONSTRAINT", "FINANCIAL_CONSTRAINT", "DURATION_CONSTRAINT", "PROGRAM_FEATURE_CONSTRAINT",
  ] as const);
  const importance = enumValue(row.importance, FIT_INTENT_IMPORTANCE);
  if (typeof row.importanceConfirmedByStudent !== "boolean" || (importance === "REQUIRED" && !row.importanceConfirmedByStudent)) invalid();
  return Object.freeze({
    dimension,
    semanticType,
    importance,
    importanceConfirmedByStudent: row.importanceConfirmedByStudent,
    typedValue: parseTypedValue(semanticType, dimension, row.typedValue),
  });
}

export function parseFitIntentCreateRequest(value: unknown) {
  const row = exact(value, ["profileVersionId", "operationId"]);
  return Object.freeze({ profileVersionId: uuid(row.profileVersionId), operationId: uuid(row.operationId) });
}

export function parseFitIntentProfileRequest(value: unknown) {
  const row = exact(value, ["profileVersionId"]);
  return Object.freeze({ profileVersionId: uuid(row.profileVersionId) });
}

export function parseFitIntentIdRequest(value: unknown) {
  const row = exact(value, ["intentSetId"]);
  return Object.freeze({ intentSetId: uuid(row.intentSetId) });
}

export function parseFitIntentRevisionRequest(value: unknown) {
  const row = exact(value, ["intentSetId", "operationId", "expectedRevision"]);
  return Object.freeze({ intentSetId: uuid(row.intentSetId), operationId: uuid(row.operationId), expectedRevision: integer(row.expectedRevision) });
}

export function parseFitIntentTaxonomyRequest(value: unknown) {
  const row = exact(value, ["intentSetId", "dimension"]);
  const dimension = enumValue(row.dimension, FIT_INTENT_DIMENSIONS);
  if (!["ACADEMIC", "CAREER", "INTERNATIONAL_ACCESSIBILITY"].includes(dimension)) invalid();
  return Object.freeze({ intentSetId: uuid(row.intentSetId), dimension: dimension as FitIntentTaxonomyOptions["dimension"] });
}

export function parseFitIntentMutationRequest(value: unknown): Readonly<{
  intentSetId: string;
  operationId: string;
  expectedRevision: number;
} & FitIntentMutation> {
  const row = exact(value, ["intentSetId", "operationId", "expectedRevision", "command", "payload"]);
  const command = enumValue(row.command, FIT_INTENT_COMMANDS);
  let mutation: FitIntentMutation;
  if (command === "DECLARATION_CREATE") {
    const payload = exact(row.payload, ["declaration"]);
    mutation = Object.freeze({ command, payload: Object.freeze({ declaration: parseDeclaration(payload.declaration) }) });
  } else if (command === "DECLARATION_REPLACE") {
    const payload = exact(row.payload, ["declarationId", "declaration"]);
    mutation = Object.freeze({ command, payload: Object.freeze({ declarationId: uuid(payload.declarationId), declaration: parseDeclaration(payload.declaration) }) });
  } else if (command === "DECLARATION_DELETE") {
    const payload = exact(row.payload, ["declarationId"]);
    mutation = Object.freeze({ command, payload: Object.freeze({ declarationId: uuid(payload.declarationId) }) });
  } else if (command === "DIMENSION_MARK_NOT_SUPPLIED") {
    const payload = exact(row.payload, ["dimension"]);
    mutation = Object.freeze({ command, payload: Object.freeze({ dimension: enumValue(payload.dimension, FIT_INTENT_DIMENSIONS) }) });
  } else if (command === "ACCESS_CONTEXT_REPLACE") {
    const keys = ["citizenshipCountryCode", "residenceCountryCode", "jurisdictionCode", "currentStatusCode", "authorizationPathCode", "targetPathCode"];
    const payload = exact(row.payload, keys, ["jurisdictionCode", "targetPathCode"]);
    const jurisdictionCode = text(payload.jurisdictionCode, 64).toUpperCase();
    const targetPathCode = text(payload.targetPathCode, 64).toUpperCase();
    const optional = (key: string) => key in payload
      ? nullableText(payload[key], 64)?.toUpperCase() ?? null
      : undefined;
    const citizenshipCountryCode = optional("citizenshipCountryCode");
    const residenceCountryCode = optional("residenceCountryCode");
    const currentStatusCode = optional("currentStatusCode");
    const authorizationPathCode = optional("authorizationPathCode");
    mutation = Object.freeze({
      command,
      payload: Object.freeze({
        ...(citizenshipCountryCode === undefined ? {} : { citizenshipCountryCode }),
        ...(residenceCountryCode === undefined ? {} : { residenceCountryCode }),
        jurisdictionCode,
        ...(currentStatusCode === undefined ? {} : { currentStatusCode }),
        ...(authorizationPathCode === undefined ? {} : { authorizationPathCode }),
        targetPathCode,
      }),
    });
  } else {
    exact(row.payload, []);
    mutation = Object.freeze({ command: "ACCESS_CONTEXT_DELETE", payload: Object.freeze({}) });
  }
  return Object.freeze({
    intentSetId: uuid(row.intentSetId),
    operationId: uuid(row.operationId),
    expectedRevision: integer(row.expectedRevision),
    ...mutation,
  });
}

function parseDocumentDeclaration(value: unknown): FitIntentDocument["declarations"][number] {
  const row = exact(value, ["declarationId", "dimension", "semanticType", "importance", "importanceConfirmedByStudent", "provenance", "typedValue"]);
  const parsed = parseDeclaration({
    dimension: row.dimension,
    semanticType: row.semanticType,
    importance: row.importance,
    importanceConfirmedByStudent: row.importanceConfirmedByStudent,
    typedValue: row.typedValue,
  });
  if (row.provenance !== "SELF_ASSERTED") invalid();
  return Object.freeze({ declarationId: uuid(row.declarationId), ...parsed, provenance: "SELF_ASSERTED" });
}

export function parseFitIntentDocument(value: unknown): FitIntentDocument {
  const row = exact(value, ["schemaVersion", "intentSetId", "profileVersionId", "versionNumber", "status", "revision", "snapshotHash", "taxonomyRelease", "dimensions", "declarations", "accessContext"]);
  if (row.schemaVersion !== "FIT_INTENT_DOCUMENT_V027") invalid();
  const status = enumValue(row.status, ["DRAFT", "FROZEN"] as const);
  const snapshotHash = row.snapshotHash === null ? null : hash(row.snapshotHash);
  if ((status === "DRAFT" && snapshotHash !== null) || (status === "FROZEN" && snapshotHash === null)) invalid();
  const taxonomy = exact(row.taxonomyRelease, ["releaseCode", "releaseOrdinal"]);
  const releaseCode = text(taxonomy.releaseCode, 64);
  if (!RELEASE_PATTERN.test(releaseCode)) invalid();
  if (!Array.isArray(row.dimensions) || row.dimensions.length !== FIT_INTENT_DIMENSIONS.length) invalid();
  const seenDimensions = new Set<string>();
  const dimensions = row.dimensions.map((entry) => {
    const state = exact(entry, ["dimension", "state"]);
    const dimension = enumValue(state.dimension, FIT_INTENT_DIMENSIONS);
    if (seenDimensions.has(dimension)) invalid();
    seenDimensions.add(dimension);
    return Object.freeze({ dimension, state: enumValue(state.state, FIT_INTENT_DIMENSION_STATES) });
  });
  if (!Array.isArray(row.declarations) || row.declarations.length > MAX_DECLARATIONS) invalid();
  const declarations = row.declarations.map(parseDocumentDeclaration);
  let accessContext: FitIntentDocument["accessContext"] = null;
  if (row.accessContext !== null) {
    const context = exact(row.accessContext, ["accessContextId", "citizenshipCountryCode", "residenceCountryCode", "jurisdictionCode", "currentStatusCode", "authorizationPathCode", "targetPathCode", "provenance"]);
    if (context.provenance !== "SELF_ASSERTED") invalid();
    accessContext = Object.freeze({
      accessContextId: uuid(context.accessContextId),
      citizenshipCountryCode: nullableText(context.citizenshipCountryCode, 64),
      residenceCountryCode: nullableText(context.residenceCountryCode, 64),
      jurisdictionCode: text(context.jurisdictionCode, 64),
      currentStatusCode: nullableText(context.currentStatusCode, 64),
      authorizationPathCode: nullableText(context.authorizationPathCode, 64),
      targetPathCode: text(context.targetPathCode, 64),
      provenance: "SELF_ASSERTED",
    });
  }
  const issues = dimensions
    .filter((entry) => entry.state === "UNANSWERED")
    .map((entry) => Object.freeze({ code: "DIMENSION_UNANSWERED" as const, dimension: entry.dimension }));
  return Object.freeze({
    schemaVersion: "FIT_INTENT_DOCUMENT_V027",
    intentSetId: uuid(row.intentSetId),
    profileVersionId: uuid(row.profileVersionId),
    versionNumber: integer(row.versionNumber, 1),
    status,
    revision: integer(row.revision),
    snapshotHash,
    taxonomyRelease: Object.freeze({ releaseCode, releaseOrdinal: integer(taxonomy.releaseOrdinal, 1) }),
    dimensions: Object.freeze(dimensions),
    declarations: Object.freeze(declarations),
    accessContext,
    readiness: Object.freeze({ freezeReady: issues.length === 0, issues: Object.freeze(issues) }),
  });
}

export function parseFitIntentDiscovery(value: unknown): FitIntentDiscovery {
  const row = exact(value, ["schemaVersion", "profileVersionId", "activeDraft", "latestFrozen"]);
  if (row.schemaVersion !== "FIT_INTENT_DISCOVERY_V027") invalid();
  return Object.freeze({
    schemaVersion: "FIT_INTENT_DISCOVERY_V027",
    profileVersionId: uuid(row.profileVersionId),
    activeDraft: row.activeDraft === null ? null : parseFitIntentDocument(row.activeDraft),
    latestFrozen: row.latestFrozen === null ? null : parseFitIntentDocument(row.latestFrozen),
  });
}

export function parseFitIntentOperationResult(value: unknown): FitIntentOperationResult {
  const row = object(value);
  if (row.schemaVersion !== "FIT_INTENT_OPERATION_RESULT_V027") invalid();
  const operation = enumValue(row.operation, ["CREATE_OR_RESUME", "MUTATE", "FREEZE"] as const);
  const keys = operation === "CREATE_OR_RESUME"
    ? ["schemaVersion", "operation", "intentSetId", "profileVersionId", "versionNumber", "status", "revision"]
    : operation === "MUTATE"
      ? ["schemaVersion", "operation", "command", "intentSetId", "revision", "resourceId", "document"]
      : ["schemaVersion", "operation", "intentSetId", "profileVersionId", "status", "revision", "snapshotHash", "document"];
  exact(row, keys);
  const result: Record<string, unknown> = {
    schemaVersion: "FIT_INTENT_OPERATION_RESULT_V027",
    operation,
    intentSetId: uuid(row.intentSetId),
    revision: integer(row.revision),
  };
  if ("profileVersionId" in row) result.profileVersionId = uuid(row.profileVersionId);
  if ("versionNumber" in row) result.versionNumber = integer(row.versionNumber, 1);
  if ("status" in row) result.status = enumValue(row.status, ["DRAFT", "FROZEN"] as const);
  if ("command" in row) result.command = enumValue(row.command, FIT_INTENT_COMMANDS);
  if ("resourceId" in row) result.resourceId = row.resourceId === null ? null : uuid(row.resourceId);
  if ("snapshotHash" in row) result.snapshotHash = hash(row.snapshotHash);
  if ("document" in row) result.document = parseFitIntentDocument(row.document);
  return Object.freeze(result) as FitIntentOperationResult;
}

export function parseFitIntentTaxonomyOptions(value: unknown): FitIntentTaxonomyOptions {
  const row = exact(value, ["schemaVersion", "intentSetId", "dimension", "releaseCode", "releaseOrdinal", "options"]);
  if (row.schemaVersion !== "FIT_INTENT_TAXONOMY_OPTIONS_V027" || !Array.isArray(row.options) || row.options.length > MAX_OPTIONS) invalid();
  const dimension = enumValue(row.dimension, ["ACADEMIC", "CAREER", "INTERNATIONAL_ACCESSIBILITY"] as const);
  const options = row.options.map((entry) => {
    const option = exact(entry, ["conceptId", "conceptKind", "canonicalKey", "displayName"]);
    return Object.freeze({ conceptId: uuid(option.conceptId), conceptKind: text(option.conceptKind, 64), canonicalKey: text(option.canonicalKey, 128), displayName: text(option.displayName, 256) });
  });
  return Object.freeze({
    schemaVersion: "FIT_INTENT_TAXONOMY_OPTIONS_V027",
    intentSetId: uuid(row.intentSetId),
    dimension,
    releaseCode: text(row.releaseCode, 64),
    releaseOrdinal: integer(row.releaseOrdinal, 1),
    options: Object.freeze(options),
  });
}

export function parseFitAccessContextOptions(value: unknown): FitAccessContextOptions {
  const row = exact(value, ["schemaVersion", "intentSetId", "options"]);
  if (row.schemaVersion !== "FIT_ACCESS_CONTEXT_OPTIONS_V027" || !Array.isArray(row.options) || row.options.length > MAX_OPTIONS) invalid();
  const options = row.options.map((entry) => {
    const option = exact(entry, ["jurisdictionCode", "targetPathCode"]);
    return Object.freeze({ jurisdictionCode: text(option.jurisdictionCode, 64), targetPathCode: text(option.targetPathCode, 64) });
  });
  return Object.freeze({ schemaVersion: "FIT_ACCESS_CONTEXT_OPTIONS_V027", intentSetId: uuid(row.intentSetId), options: Object.freeze(options) });
}
