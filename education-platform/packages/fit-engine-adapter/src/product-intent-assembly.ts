import { FIT_DIMENSIONS, type FitDimension } from "@education-platform/fit-engine";
import { FitAdapterError } from "./database-gateway.js";
import type { FitEvaluationRequest, ProductFitEvaluationRequest } from "./request.js";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const HASH_PATTERN = /^[a-f0-9]{64}$/;
const RELEASE_PATTERN = /^[A-Za-z0-9._-]{1,64}$/;
const MAX_DECLARATIONS = 64;

const dimensionDomain: Readonly<Record<FitDimension, "GOALS" | "PREFERENCES">> = {
  ACADEMIC: "GOALS",
  CAREER: "GOALS",
  FINANCIAL: "PREFERENCES",
  GEOGRAPHIC_DELIVERY: "PREFERENCES",
  PERSONAL_PREFERENCE: "PREFERENCES",
  INTERNATIONAL_ACCESSIBILITY: "GOALS",
};

export type ProductFitIntentDimension = Readonly<{
  dimension: FitDimension;
  disposition: "DECLARED" | "EXPLICIT_NOT_SUPPLIED";
  inputAvailability: "INCLUDED" | "NOT_SUPPLIED";
  completenessDomain: "GOALS" | "PREFERENCES";
  completenessId: string;
  profileCompleteness: "COMPLETE" | "PARTIAL" | "UNKNOWN";
}>;

export type ProductFitIntentDeclaration = Readonly<{
  declarationId: string;
  dimension: FitDimension;
  semanticType: "TAXONOMY_TARGET" | "DELIVERY_CONSTRAINT" | "FINANCIAL_CONSTRAINT" | "DURATION_CONSTRAINT" | "PROGRAM_FEATURE_CONSTRAINT";
  taxonomyConceptId: string | null;
}>;

export type ProductFitIntentAssembly = Readonly<{
  schemaVersion: "FIT_EVALUATION_ASSEMBLY_V027";
  profileVersionId: string;
  intentSetId: string;
  programVersionId: string;
  intentSnapshotHash: string;
  taxonomyReleaseCode: string;
  taxonomyReleaseOrdinal: number;
  dimensions: readonly ProductFitIntentDimension[];
  declarations: readonly ProductFitIntentDeclaration[];
  accessContextId: string | null;
}>;

function invalid(label: string): never {
  throw new FitAdapterError(`Authoritative M027 Fit assembly is invalid: ${label}`, 500);
}

function object(value: unknown, label: string): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return invalid(label);
  return value as Record<string, unknown>;
}

function exactKeys(value: Record<string, unknown>, keys: readonly string[], label: string): void {
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  if (actual.length !== expected.length || actual.some((key, index) => key !== expected[index])) invalid(label);
}

function boundedText(value: unknown, label: string, maximum = 256): string {
  if (typeof value !== "string" || value.length === 0 || new TextEncoder().encode(value).length > maximum) return invalid(label);
  return value;
}

function uuid(value: unknown, label: string): string {
  const result = boundedText(value, label, 36).toLowerCase();
  if (!UUID_PATTERN.test(result)) return invalid(label);
  return result;
}

function hash(value: unknown, label: string): string {
  const result = boundedText(value, label, 64);
  if (!HASH_PATTERN.test(result)) return invalid(label);
  return result;
}

function integer(value: unknown, label: string, minimum = 0): number {
  if (!Number.isSafeInteger(value) || (value as number) < minimum) return invalid(label);
  return value as number;
}

function enumeration<T extends readonly string[]>(value: unknown, values: T, label: string): T[number] {
  if (typeof value !== "string" || !(values as readonly unknown[]).includes(value)) return invalid(label);
  return value as T[number];
}

function nullableText(value: unknown, label: string, maximum = 64): string | null {
  return value === null ? null : boundedText(value, label, maximum);
}

function finiteNumber(value: unknown, label: string): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) return invalid(label);
  return value;
}

function parseTypedValue(
  semanticType: ProductFitIntentDeclaration["semanticType"],
  dimension: FitDimension,
  value: unknown,
): string | null {
  const row = object(value, "declaration typedValue");
  if (semanticType === "TAXONOMY_TARGET") {
    if (!["ACADEMIC", "CAREER", "INTERNATIONAL_ACCESSIBILITY"].includes(dimension)) invalid("taxonomy declaration dimension");
    exactKeys(row, ["conceptId", "relation"], "taxonomy typedValue");
    enumeration(row.relation, ["DESIRED", "EXCLUDED"] as const, "taxonomy relation");
    return uuid(row.conceptId, "taxonomy conceptId");
  }
  if (semanticType === "DELIVERY_CONSTRAINT") {
    if (dimension !== "GEOGRAPHIC_DELIVERY") invalid("delivery declaration dimension");
    exactKeys(row, ["deliveryMode", "relation"], "delivery typedValue");
    enumeration(row.deliveryMode, ["IN_PERSON", "ONLINE", "HYBRID"] as const, "deliveryMode");
    enumeration(row.relation, ["DESIRED", "EXCLUDED"] as const, "delivery relation");
    return null;
  }
  if (semanticType === "FINANCIAL_CONSTRAINT") {
    if (dimension !== "FINANCIAL") invalid("financial declaration dimension");
    exactKeys(row, ["amount", "constraintSemantics", "currency", "scope", "period", "basis", "components"], "financial typedValue");
    finiteNumber(row.amount, "financial amount");
    enumeration(row.constraintSemantics, ["HARD_TOTAL_COST_CEILING", "PREFERRED_TOTAL_COST", "HARD_TUITION_CEILING", "PREFERRED_TUITION"] as const, "financial semantics");
    if (!/^[A-Z]{3}$/.test(boundedText(row.currency, "financial currency", 3))) invalid("financial currency");
    const scope = enumeration(row.scope, ["COMPONENT", "TOTAL_COST"] as const, "financial scope");
    enumeration(row.period, ["MONTH", "ACADEMIC_YEAR", "CALENDAR_YEAR", "PROGRAM_DURATION", "ACADEMIC_SEMESTER", "CREDIT"] as const, "financial period");
    if (row.basis !== "GROSS" || !Array.isArray(row.components) || row.components.length !== 1) invalid("financial basis/components");
    const component = enumeration(row.components[0], ["TUITION", "TOTAL_COST"] as const, "financial component");
    if ((scope === "TOTAL_COST") !== (component === "TOTAL_COST")) invalid("financial scope/component pairing");
    return null;
  }
  if (semanticType === "DURATION_CONSTRAINT") {
    if (dimension !== "PERSONAL_PREFERENCE") invalid("duration declaration dimension");
    exactKeys(row, ["minimumMonths", "maximumMonths"], "duration typedValue");
    const minimum = row.minimumMonths === null ? null : finiteNumber(row.minimumMonths, "minimumMonths");
    const maximum = row.maximumMonths === null ? null : finiteNumber(row.maximumMonths, "maximumMonths");
    if (minimum === null && maximum === null || minimum !== null && maximum !== null && maximum < minimum) invalid("duration bounds");
    return null;
  }
  if (dimension !== "PERSONAL_PREFERENCE") invalid("program feature declaration dimension");
  exactKeys(row, ["featureKey", "expected"], "program feature typedValue");
  if (row.featureKey !== "CAPSTONE_AVAILABLE" || typeof row.expected !== "boolean") invalid("program feature typedValue");
  return null;
}

export function parseProductFitIntentAssembly(value: unknown): ProductFitIntentAssembly {
  const assembly = object(value, "assembly");
  exactKeys(assembly, ["schemaVersion", "profileVersionId", "intentSetId", "programVersionId", "intentSnapshotHash", "dimensions", "intentDocument"], "assembly keys");
  if (assembly.schemaVersion !== "FIT_EVALUATION_ASSEMBLY_V027") invalid("assembly schemaVersion");
  if (!Array.isArray(assembly.dimensions) || assembly.dimensions.length !== FIT_DIMENSIONS.length) invalid("assembly dimensions");

  const dimensions = assembly.dimensions.map((value, index) => {
    const row = object(value, `dimensions[${index}]`);
    exactKeys(row, ["dimension", "disposition", "inputAvailability", "completenessDomain", "completenessId", "profileCompleteness"], `dimensions[${index}] keys`);
    const dimension = enumeration(row.dimension, FIT_DIMENSIONS, `dimensions[${index}].dimension`);
    const disposition = enumeration(row.disposition, ["DECLARED", "EXPLICIT_NOT_SUPPLIED"] as const, `dimensions[${index}].disposition`);
    const inputAvailability = enumeration(row.inputAvailability, ["INCLUDED", "NOT_SUPPLIED"] as const, `dimensions[${index}].inputAvailability`);
    const completenessDomain = enumeration(row.completenessDomain, ["GOALS", "PREFERENCES"] as const, `dimensions[${index}].completenessDomain`);
    if ((disposition === "DECLARED") !== (inputAvailability === "INCLUDED") || completenessDomain !== dimensionDomain[dimension]) invalid(`dimensions[${index}] semantic mapping`);
    return Object.freeze({
      dimension,
      disposition,
      inputAvailability,
      completenessDomain,
      completenessId: uuid(row.completenessId, `dimensions[${index}].completenessId`),
      profileCompleteness: enumeration(row.profileCompleteness, ["COMPLETE", "PARTIAL", "UNKNOWN"] as const, `dimensions[${index}].profileCompleteness`),
    });
  });
  if (new Set(dimensions.map((row) => row.dimension)).size !== FIT_DIMENSIONS.length) invalid("duplicate dimensions");

  const document = object(assembly.intentDocument, "intentDocument");
  exactKeys(document, ["schemaVersion", "intentSetId", "profileVersionId", "versionNumber", "status", "revision", "snapshotHash", "taxonomyRelease", "dimensions", "declarations", "accessContext"], "intentDocument keys");
  if (document.schemaVersion !== "FIT_INTENT_DOCUMENT_V027" || document.status !== "FROZEN") invalid("intentDocument identity/status");
  integer(document.versionNumber, "intentDocument.versionNumber", 1);
  integer(document.revision, "intentDocument.revision");

  const documentDimensions = document.dimensions;
  if (!Array.isArray(documentDimensions) || documentDimensions.length !== FIT_DIMENSIONS.length) invalid("intentDocument dimensions");
  const documentState = new Map<FitDimension, ProductFitIntentDimension["disposition"]>();
  for (const [index, value] of documentDimensions.entries()) {
    const row = object(value, `intentDocument.dimensions[${index}]`);
    exactKeys(row, ["dimension", "state"], `intentDocument.dimensions[${index}] keys`);
    const dimension = enumeration(row.dimension, FIT_DIMENSIONS, `intentDocument.dimensions[${index}].dimension`);
    const state = enumeration(row.state, ["DECLARED", "EXPLICIT_NOT_SUPPLIED"] as const, `intentDocument.dimensions[${index}].state`);
    if (documentState.has(dimension)) invalid("duplicate intentDocument dimensions");
    documentState.set(dimension, state);
  }

  if (!Array.isArray(document.declarations) || document.declarations.length > MAX_DECLARATIONS) invalid("intentDocument declarations");
  const declarations = document.declarations.map((value, index) => {
    const row = object(value, `intentDocument.declarations[${index}]`);
    exactKeys(row, ["declarationId", "dimension", "semanticType", "importance", "importanceConfirmedByStudent", "provenance", "typedValue"], `intentDocument.declarations[${index}] keys`);
    const dimension = enumeration(row.dimension, FIT_DIMENSIONS, `intentDocument.declarations[${index}].dimension`);
    const semanticType = enumeration(row.semanticType, ["TAXONOMY_TARGET", "DELIVERY_CONSTRAINT", "FINANCIAL_CONSTRAINT", "DURATION_CONSTRAINT", "PROGRAM_FEATURE_CONSTRAINT"] as const, `intentDocument.declarations[${index}].semanticType`);
    const importance = enumeration(row.importance, ["REQUIRED", "STRONGLY_PREFERRED", "PREFERRED", "NEUTRAL", "UNSPECIFIED"] as const, `intentDocument.declarations[${index}].importance`);
    if (typeof row.importanceConfirmedByStudent !== "boolean" || importance === "REQUIRED" && !row.importanceConfirmedByStudent || row.provenance !== "SELF_ASSERTED") invalid(`intentDocument.declarations[${index}] authority`);
    return Object.freeze({
      declarationId: uuid(row.declarationId, `intentDocument.declarations[${index}].declarationId`),
      dimension,
      semanticType,
      taxonomyConceptId: parseTypedValue(semanticType, dimension, row.typedValue),
    });
  });
  if (new Set(declarations.map((row) => row.declarationId)).size !== declarations.length) invalid("duplicate declaration IDs");

  for (const dimension of FIT_DIMENSIONS) {
    const outer = dimensions.find((row) => row.dimension === dimension)!;
    const declarationCount = declarations.filter((row) => row.dimension === dimension).length;
    if (documentState.get(dimension) !== outer.disposition
      || outer.disposition === "DECLARED" && declarationCount === 0
      || outer.disposition === "EXPLICIT_NOT_SUPPLIED" && declarationCount !== 0) {
      invalid(`${dimension} disposition/declaration consistency`);
    }
  }

  let accessContextId: string | null = null;
  if (document.accessContext !== null) {
    const context = object(document.accessContext, "intentDocument.accessContext");
    exactKeys(context, ["accessContextId", "citizenshipCountryCode", "residenceCountryCode", "jurisdictionCode", "currentStatusCode", "authorizationPathCode", "targetPathCode", "provenance"], "intentDocument.accessContext keys");
    accessContextId = uuid(context.accessContextId, "intentDocument.accessContext.accessContextId");
    nullableText(context.citizenshipCountryCode, "citizenshipCountryCode");
    nullableText(context.residenceCountryCode, "residenceCountryCode");
    boundedText(context.jurisdictionCode, "jurisdictionCode", 64);
    nullableText(context.currentStatusCode, "currentStatusCode");
    nullableText(context.authorizationPathCode, "authorizationPathCode");
    boundedText(context.targetPathCode, "targetPathCode", 64);
    if (context.provenance !== "SELF_ASSERTED" || documentState.get("INTERNATIONAL_ACCESSIBILITY") !== "DECLARED") invalid("accessContext provenance/dimension");
  }

  const taxonomy = object(document.taxonomyRelease, "intentDocument.taxonomyRelease");
  exactKeys(taxonomy, ["releaseCode", "releaseOrdinal"], "intentDocument.taxonomyRelease keys");
  const taxonomyReleaseCode = boundedText(taxonomy.releaseCode, "taxonomy releaseCode", 64);
  if (!RELEASE_PATTERN.test(taxonomyReleaseCode)) invalid("taxonomy releaseCode");

  const profileVersionId = uuid(assembly.profileVersionId, "assembly.profileVersionId");
  const intentSetId = uuid(assembly.intentSetId, "assembly.intentSetId");
  const intentSnapshotHash = hash(assembly.intentSnapshotHash, "assembly.intentSnapshotHash");
  if (profileVersionId !== uuid(document.profileVersionId, "intentDocument.profileVersionId")
    || intentSetId !== uuid(document.intentSetId, "intentDocument.intentSetId")
    || intentSnapshotHash !== hash(document.snapshotHash, "intentDocument.snapshotHash")) {
    invalid("assembly/document identity binding");
  }

  return Object.freeze({
    schemaVersion: "FIT_EVALUATION_ASSEMBLY_V027",
    profileVersionId,
    intentSetId,
    programVersionId: uuid(assembly.programVersionId, "assembly.programVersionId"),
    intentSnapshotHash,
    taxonomyReleaseCode,
    taxonomyReleaseOrdinal: integer(taxonomy.releaseOrdinal, "taxonomy releaseOrdinal", 1),
    dimensions: Object.freeze(dimensions),
    declarations: Object.freeze(declarations),
    accessContextId,
  });
}

export function taxonomyConceptIdsFromProductAssembly(assembly: ProductFitIntentAssembly): readonly string[] {
  return Object.freeze([...new Set(assembly.declarations.flatMap((row) => row.taxonomyConceptId === null ? [] : [row.taxonomyConceptId]))].sort());
}

export function fitEvaluationRequestFromProductAssembly(
  request: ProductFitEvaluationRequest,
  assembly: ProductFitIntentAssembly,
): FitEvaluationRequest {
  if (request.profileVersionId !== assembly.profileVersionId
    || request.intentSetId !== assembly.intentSetId
    || request.programVersionId !== assembly.programVersionId) {
    throw new FitAdapterError("Product Fit request does not match its authoritative M027 assembly", 409);
  }
  return {
    profileVersionId: assembly.profileVersionId,
    intentSetId: assembly.intentSetId,
    programVersionId: assembly.programVersionId,
    taxonomyReleaseCode: assembly.taxonomyReleaseCode,
    supersedesEvaluationId: null,
    eligibilityContextEvaluationId: request.eligibilityContextEvaluationId,
    evidence: {
      canonicalObservationIds: [],
      catalogMappingIds: [],
      studentCourseIds: [],
      studentMappingIds: [],
      taxonomyConceptIds: taxonomyConceptIdsFromProductAssembly(assembly),
      contextClaimIds: [],
      contextMappingIds: [],
      accessContextId: assembly.accessContextId,
      directFinancialComparisons: [],
      approvedFinancialNormalizationIds: [],
    },
  };
}
