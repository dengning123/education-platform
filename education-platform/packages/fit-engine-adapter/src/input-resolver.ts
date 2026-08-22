import {
  FIT_DIMENSIONS,
  type DecisionManifestItem,
  type FitDimension,
  type FitEvaluationInput,
  type FinancialComparable,
  type FitInputPolicyKey,
  type FitIntent,
  type FitMethodCode,
  type ManifestRef,
  type ProgramFact,
  type ResolvedFitContract,
  type ResolvedMethodContract,
} from "@education-platform/fit-engine";
import { FitAdapterError, postgresIn, requireOne, type FitDatabaseGateway } from "./database-gateway.js";
import { calculateReviewedFinancialNormalization, equalExactDecimals } from "./financial-normalization.js";
import type { DirectFinancialSelection, FitEvaluationRequest } from "./request.js";

type ProfileRow = { profile_version_id: string; snapshot_hash: string | null; status: string };
type IntentSetRow = { intent_set_id: string; profile_version_id: string; snapshot_hash: string | null; status: string };
type IntentRow = {
  intent_declaration_id: string;
  intent_set_id: string;
  profile_version_id: string;
  dimension: FitDimension;
  semantic_type: FitIntent["kind"];
  importance: FitIntent["authority"]["importance"];
  importance_basis: FitIntent["authority"]["basis"];
  importance_evidence_id: string | null;
  importance_confirmed_by_student: boolean;
  source_student_goal_id: string | null;
  source_student_preference_id: string | null;
};
type GoalRow = { student_goal_id: string; profile_version_id: string; goal_type: string; concept_id: string | null; goal_text: string | null };
type PreferenceRow = { student_preference_id: string; profile_version_id: string; preference_type: string; value: unknown };
type CourseRow = { student_course_id: string; profile_version_id: string; course_code: string | null; course_title: string; course_status: string; term: string | null };
type StudentMappingRow = { student_mapping_id: string; profile_version_id: string; student_record_id: string; concept_id: string; mapping_status: string; reviewed_at: string | null; student_evidence_id: string | null; retired_at: string | null };
type ObservationRow = { observation_id: string; record_type: ProgramFact["recordType"]; record_id: string; field_name: ProgramFact["field"]; observed_value: unknown; knowledge_status: string };
type CanonicalSelectionRow = { observation_id: string; record_type: string; record_id: string; field_name: string };
type CatalogMappingRow = { mapping_id: string; record_type: string; record_id: string; concept_id: string; relation: string; mapping_status: string; reviewed_at: string | null; verification_evidence_id: string | null; retired_at: string | null };
type TaxonomyConceptRow = { concept_id: string; introduced_in_release: string; retired_in_release: string | null };
type TaxonomyReleaseRow = { release_code: string; release_ordinal: number };
type ContextClaimRow = { context_claim_id: string; claim_definition_id: string; program_version_id: string | null; geography_code: string | null; jurisdiction_code: string | null; path_code: string | null; valid_from: string; valid_to: string | null };
type ContextDefinitionRow = { claim_definition_id: string; claim_code: string; semantic_source_class_code: string };
type ContextSelectionRow = { context_claim_id: string; context_selection_id: string; context_observation_id: string | null; knowledge_status: string };
type ContextObservationRow = { context_observation_id: string; context_claim_id: string; observed_value: Record<string, unknown>; authority: string; workflow_status: string; reviewed_at: string | null };
type ContextMappingRow = { context_mapping_id: string; context_claim_id: string; concept_id: string; relation_code: string; mapping_status: string; reviewed_at: string | null; verification_evidence_id: string | null; retired_at: string | null };
type AccessContextRow = { access_context_id: string; citizenship_country_code: string | null; residence_country_code: string | null; jurisdiction_code: string | null; current_status_code: string | null; authorization_path_code: string | null; target_path_code: string | null };
type ProgramCostRow = { cost_id: string; program_version_id: string; currency: string | null; billing_basis: string | null };
type FinancialNormalizationRow = {
  financial_normalization_id: string;
  evaluation_id: string;
  profile_version_id: string;
  field_observation_id: string;
  financial_constraint_id: string;
  intent_set_id: string;
  normalization_method_id: string;
  conversion_evidence_id: string;
  original_amount: string | number;
  original_currency: string;
  original_period: FinancialComparable["period"];
  original_scope: FinancialComparable["scope"];
  original_basis: FinancialComparable["basis"];
  original_components: string[];
  target_amount: string | number;
  target_currency: string;
  target_period: FinancialComparable["period"];
  target_scope: FinancialComparable["scope"];
  target_basis: FinancialComparable["basis"];
  target_components: string[];
};
type FinancialNormalizationReviewRow = {
  financial_normalization_id: string;
  evaluation_id: string;
  status: string;
  verification_evidence_id: string | null;
  retired_at: string | null;
};
type FinancialSourcePinRow = {
  evaluation_id: string;
  amount_observation_id: string;
  billing_basis_observation_id: string;
};
type FinancialConversionInputRow = {
  financial_normalization_id: string;
  input_role: "SOURCE_AMOUNT" | "ACADEMIC_YEARS" | "AVAILABLE_FUNDING" | "ROUNDING";
  numeric_value: string | number | null;
  text_value: string | null;
  unit: string;
};

const methodCodeByDimension: Readonly<Record<FitDimension, FitMethodCode>> = {
  ACADEMIC: "ACADEMIC_ALIGNMENT_V01",
  CAREER: "CAREER_ALIGNMENT_V01",
  FINANCIAL: "FINANCIAL_ALIGNMENT_V01",
  GEOGRAPHIC_DELIVERY: "GEOGRAPHIC_DELIVERY_ALIGNMENT_V01",
  PERSONAL_PREFERENCE: "PERSONAL_PREFERENCE_ALIGNMENT_V01",
  INTERNATIONAL_ACCESSIBILITY: "INTERNATIONAL_ACCESSIBILITY_V01",
};

function methodFor(contract: ResolvedFitContract, dimension: FitDimension): ResolvedMethodContract {
  return contract.methods[dimension];
}

function policyFor(method: ResolvedMethodContract, domain: string, field?: string) {
  const rows = method.inputPolicies.filter((policy) =>
    policy.disposition === "ALLOWED" && policy.inputDomain === domain && (field === undefined || policy.fieldName === field));
  return requireOne(rows, `${method.dimension} ${domain}${field === undefined ? "" : `/${field}`} policy`);
}

function ref(
  method: ResolvedMethodContract,
  policy: ReturnType<typeof policyFor>,
  manifestItemKey: string,
  sourceId: string,
  sourceClass: ManifestRef["sourceClass"],
  authorityRole: ManifestRef["authorityRole"],
): ManifestRef {
  return {
    manifestItemKey,
    sourceId,
    methodRegistryId: method.identity.id,
    inputPolicyRegistryId: policy.identity.id,
    methodCode: method.identity.code as FitMethodCode,
    policyKey: policy.policyKey,
    sourceClass,
    authorityRole,
  };
}

function isoDate(value: string): string {
  return value.includes("T") ? value : `${value}T00:00:00.000Z`;
}

function decimal(value: unknown, label: string): string {
  if ((typeof value !== "number" && typeof value !== "string") || !/^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$/.test(String(value))) {
    throw new FitAdapterError(`${label} is not an exact decimal`, 422);
  }
  return String(value);
}

function typedContextValue(claimCode: string, value: Record<string, unknown>) {
  switch (claimCode) {
    case "REGULATORY_WORK_AUTHORIZATION":
      return { claimCode, allowed: Boolean(value.allowed), authorizationType: value.authorizationType === null ? null : String(value.authorizationType) } as const;
    case "LICENSING_RESTRICTION":
      return { claimCode, restricted: Boolean(value.restricted), licenseType: value.licenseType === null ? null : String(value.licenseType) } as const;
    case "CITIZENSHIP_SECURITY_CLEARANCE_RESTRICTION":
      return { claimCode, restricted: Boolean(value.restricted), citizenships: Array.isArray(value.citizenships) ? value.citizenships.map(String) : [], clearanceType: value.clearanceType === null ? null : String(value.clearanceType) } as const;
    case "JURISDICTION_PATH_ACCESSIBILITY":
      return { claimCode, accessible: Boolean(value.accessible), restrictionCode: value.restrictionCode === null ? null : String(value.restrictionCode) } as const;
    case "REVIEWED_CAREER_OUTCOME": {
      const scope = value.applicabilityScope;
      if (scope === null || typeof scope !== "object" || Array.isArray(scope)) throw new FitAdapterError("Career context lacks applicabilityScope", 422);
      const applicability = scope as Record<string, unknown>;
      return {
        claimCode,
        outcome: String(value.outcome),
        populationDenominator: String(value.populationDenominator),
        cohortPeriod: String(value.cohortPeriod),
        geography: String(value.geography),
        reportingCoverage: String(value.reportingCoverage),
        outcomeDefinition: String(value.outcomeDefinition),
        sampleSource: String(value.sampleSource),
        applicabilityScope: {
          population: String(applicability.population),
          program: String(applicability.program),
          geography: String(applicability.geography),
          period: String(applicability.period),
        },
      } as const;
    }
    default:
      throw new FitAdapterError(`Unsupported context claim code ${claimCode}`, 422);
  }
}

async function typedIntent(
  database: FitDatabaseGateway,
  row: IntentRow,
  manifestItemKey: string,
): Promise<FitIntent> {
  const authority = {
    importance: row.importance,
    basis: row.importance_basis,
    importanceEvidenceManifestKey: row.importance === "REQUIRED" ? manifestItemKey : null,
    confirmedByStudent: row.importance_confirmed_by_student,
  } as const;
  const query = { select: "*", intent_declaration_id: `eq.${row.intent_declaration_id}` };
  switch (row.semantic_type) {
    case "TAXONOMY_TARGET": {
      const child = requireOne(await database.select<{ concept_id: string; relation: "DESIRED" | "EXCLUDED" }>("fit_intent_taxonomy_targets", query), "taxonomy intent child");
      return { kind: "TAXONOMY_TARGET", intentId: row.intent_declaration_id, dimension: row.dimension as "ACADEMIC" | "CAREER" | "INTERNATIONAL_ACCESSIBILITY", authority, conceptId: child.concept_id, relation: child.relation };
    }
    case "LOCATION_CONSTRAINT": {
      const child = requireOne(await database.select<{ relation: "PREFERRED" | "ACCEPTABLE" | "REQUIRED" | "EXCLUDED"; country_code: string | null; region_code: string | null; locality: string | null }>("fit_intent_location_constraints", query), "location intent child");
      return { kind: "LOCATION_CONSTRAINT", intentId: row.intent_declaration_id, dimension: "GEOGRAPHIC_DELIVERY", authority, relation: child.relation, countryCode: child.country_code, regionCode: child.region_code, locality: child.locality };
    }
    case "DELIVERY_CONSTRAINT": {
      const child = requireOne(await database.select<{ delivery_mode: "IN_PERSON" | "ONLINE" | "HYBRID"; relation: "DESIRED" | "EXCLUDED" }>("fit_intent_delivery_constraints", query), "delivery intent child");
      return { kind: "DELIVERY_CONSTRAINT", intentId: row.intent_declaration_id, dimension: "GEOGRAPHIC_DELIVERY", authority, deliveryMode: child.delivery_mode, relation: child.relation };
    }
    case "FINANCIAL_CONSTRAINT": {
      const child = requireOne(await database.select<{ amount: string | number; constraint_semantics: "HARD_TOTAL_COST_CEILING" | "PREFERRED_TOTAL_COST" | "HARD_TUITION_CEILING" | "PREFERRED_TUITION" | "AVAILABLE_FUNDING"; currency: string; financial_scope: "COMPONENT" | "PARTIAL_TOTAL" | "TOTAL_COST"; financial_period: "MONTH" | "ACADEMIC_YEAR" | "CALENDAR_YEAR" | "PROGRAM_DURATION"; financial_basis: "GROSS" | "NET_OF_VERIFIED_FUNDING"; components: string[] }>("fit_intent_financial_constraints", query), "financial intent child");
      return { kind: "FINANCIAL_CONSTRAINT", intentId: row.intent_declaration_id, dimension: "FINANCIAL", authority, amount: decimal(child.amount, "financial intent amount"), semantics: child.constraint_semantics, currency: child.currency.trim(), scope: child.financial_scope, period: child.financial_period, basis: child.financial_basis, components: child.components };
    }
    case "DURATION_CONSTRAINT": {
      const child = requireOne(await database.select<{ minimum_months: string | number | null; maximum_months: string | number | null }>("fit_intent_duration_constraints", query), "duration intent child");
      return { kind: "DURATION_CONSTRAINT", intentId: row.intent_declaration_id, dimension: "PERSONAL_PREFERENCE", authority, minimumMonths: child.minimum_months === null ? null : decimal(child.minimum_months, "minimum months"), maximumMonths: child.maximum_months === null ? null : decimal(child.maximum_months, "maximum months") };
    }
    case "PROGRAM_FEATURE_CONSTRAINT": {
      const child = requireOne(await database.select<{ feature_key: "CAPSTONE_AVAILABLE" | "RESEARCH_OPPORTUNITY" | "FACULTY_ACCESS" | "COHORT_STRUCTURE" | "INTERNATIONAL_PATH_SUPPORT"; expected: boolean }>("fit_intent_program_feature_constraints", query), "program feature intent child");
      return { kind: "PROGRAM_FEATURE_CONSTRAINT", intentId: row.intent_declaration_id, dimension: row.dimension as "PERSONAL_PREFERENCE" | "INTERNATIONAL_ACCESSIBILITY", authority, feature: child.feature_key, expected: child.expected };
    }
  }
}

function programFact(row: ObservationRow): ProgramFact {
  const value = row.observed_value;
  if (row.record_type === "PROGRAM_COURSE" && (row.field_name === "course_name" || row.field_name === "official_description")) {
    return { recordType: "PROGRAM_COURSE", field: row.field_name, value: String(value) };
  }
  if (row.record_type === "PROGRAM_COST" && ["tuition_amount", "mandatory_fees", "estimated_living_cost", "estimated_total_cost", "currency", "billing_basis"].includes(row.field_name)) {
    return { recordType: "PROGRAM_COST", field: row.field_name as Extract<ProgramFact, { recordType: "PROGRAM_COST" }>["field"], value: String(value) };
  }
  if (row.record_type === "PROGRAM_VERSION") {
    if (row.field_name === "delivery_mode") return { recordType: "PROGRAM_VERSION", field: "delivery_mode", value: String(value) as "IN_PERSON" | "ONLINE" | "HYBRID" | "UNKNOWN" };
    if (row.field_name === "duration_months") return { recordType: "PROGRAM_VERSION", field: "duration_months", value: decimal(value, "duration_months") };
    if (row.field_name === "full_time" || row.field_name === "capstone_required") return { recordType: "PROGRAM_VERSION", field: row.field_name, value: Boolean(value) };
    if (row.field_name === "stem_status") return { recordType: "PROGRAM_VERSION", field: "stem_status", value: String(value) };
  }
  throw new FitAdapterError(`Unsupported canonical field ${row.record_type}.${row.field_name}`, 422);
}

function directComparable(
  selection: DirectFinancialSelection,
  amount: ObservationRow,
  basis: ObservationRow,
  cost: ProgramCostRow,
  intent: Extract<FitIntent, { kind: "FINANCIAL_CONSTRAINT" }>,
): FinancialComparable {
  if (amount.record_type !== "PROGRAM_COST" || basis.record_type !== "PROGRAM_COST" || amount.record_id !== basis.record_id || basis.field_name !== "billing_basis") {
    throw new FitAdapterError("Direct Financial observations must be an amount/billing-basis pair on one cost row", 422);
  }
  const field = amount.field_name;
  const scope = field === "estimated_total_cost" ? "TOTAL_COST" as const : "COMPONENT" as const;
  const component = field === "tuition_amount" ? "TUITION"
    : field === "mandatory_fees" ? "MANDATORY_FEES"
      : field === "estimated_living_cost" ? "LIVING_COST"
        : field === "estimated_total_cost" ? "TOTAL_COST" : null;
  const period: FinancialComparable["period"] | null = basis.observed_value === "PER_YEAR" ? "ACADEMIC_YEAR"
    : basis.observed_value === "TOTAL_PROGRAM" ? "PROGRAM_DURATION" : null;
  if (component === null || period === null || cost.currency === null || cost.billing_basis !== basis.observed_value) {
    throw new FitAdapterError("Direct Financial source is not v014-comparable", 422);
  }
  const comparable = { amount: decimal(amount.observed_value, "program amount"), currency: cost.currency.trim(), period, scope, basis: "GROSS" as const, components: [component] };
  if (intent.intentId !== selection.financialIntentId || intent.currency !== comparable.currency || intent.period !== comparable.period || intent.scope !== comparable.scope || intent.basis !== comparable.basis || [...intent.components].sort().join("\0") !== [...comparable.components].sort().join("\0")) {
    throw new FitAdapterError("Direct Financial tuple does not exactly match its frozen intent", 422);
  }
  return comparable;
}

export async function resolveFitEvaluationInput(
  database: FitDatabaseGateway,
  contract: ResolvedFitContract,
  request: FitEvaluationRequest,
  evaluationAsOf: string,
): Promise<FitEvaluationInput> {
  const [profile, intentSet] = await Promise.all([
    database.select<ProfileRow>("student_profile_versions", { select: "profile_version_id,snapshot_hash,status", profile_version_id: `eq.${request.profileVersionId}` }).then((rows) => requireOne(rows, "profile version")),
    database.select<IntentSetRow>("fit_intent_sets", { select: "intent_set_id,profile_version_id,snapshot_hash,status", intent_set_id: `eq.${request.intentSetId}` }).then((rows) => requireOne(rows, "intent set")),
  ]);
  if (profile.status !== "FROZEN" || profile.snapshot_hash === null || intentSet.status !== "FROZEN" || intentSet.snapshot_hash === null || intentSet.profile_version_id !== profile.profile_version_id) {
    throw new FitAdapterError("Fit input requires matching frozen profile and intent snapshots", 409);
  }
  const intents = await database.select<IntentRow>("fit_intent_declarations", { select: "*", intent_set_id: `eq.${request.intentSetId}`, order: "dimension,intent_declaration_id" });
  const manifest: DecisionManifestItem[] = [];
  const intentById = new Map<string, FitIntent>();
  for (const row of intents) {
    const method = methodFor(contract, row.dimension);
    const policy = policyFor(method, "FIT_INTENTS");
    const key = `intent:${method.identity.id}:${row.intent_declaration_id}`;
    const intent = await typedIntent(database, row, key);
    intentById.set(row.intent_declaration_id, intent);
    manifest.push({ kind: "FIT_INTENT", ref: ref(method, policy, key, row.intent_declaration_id, "STUDENT_RAW_INTENT", "AUTHORITATIVE"), intent });
    if (row.source_student_goal_id !== null) {
      const source = requireOne(await database.select<GoalRow>("student_goals", { select: "student_goal_id,profile_version_id,goal_type,concept_id,goal_text", student_goal_id: `eq.${row.source_student_goal_id}`, profile_version_id: `eq.${request.profileVersionId}` }), "source student goal");
      const sourcePolicy = policyFor(method, "STUDENT_GOALS");
      manifest.push({ kind: "PHASE2_GOAL", ref: ref(method, sourcePolicy, `goal:${method.identity.id}:${source.student_goal_id}`, source.student_goal_id, "STUDENT_RAW_INTENT", "AUTHORITATIVE"), exposedFields: ["GOAL_TYPE", "CONCEPT_ID", "GOAL_TEXT"], goalType: source.goal_type, conceptId: source.concept_id, goalText: source.goal_text });
    }
    if (row.source_student_preference_id !== null) {
      const source = requireOne(await database.select<PreferenceRow>("student_preferences", { select: "student_preference_id,profile_version_id,preference_type,value", student_preference_id: `eq.${row.source_student_preference_id}`, profile_version_id: `eq.${request.profileVersionId}` }), "source student preference");
      const sourcePolicy = policyFor(method, "STUDENT_PREFERENCES");
      manifest.push({ kind: "PHASE2_PREFERENCE", ref: ref(method, sourcePolicy, `preference:${method.identity.id}:${source.student_preference_id}`, source.student_preference_id, "STUDENT_RAW_INTENT", "AUTHORITATIVE"), exposedFields: ["PREFERENCE_TYPE", "VALUE"], preferenceType: source.preference_type, value: JSON.stringify(source.value) });
    }
  }

  if (request.evidence.studentCourseIds.length > 0) {
    const rows = await database.select<CourseRow>("student_courses", { select: "student_course_id,profile_version_id,course_code,course_title,course_status,term", profile_version_id: `eq.${request.profileVersionId}`, student_course_id: postgresIn(request.evidence.studentCourseIds) });
    if (rows.length !== request.evidence.studentCourseIds.length) throw new FitAdapterError("A selected student course is outside the profile", 422);
    const method = contract.methods.ACADEMIC;
    const policy = policyFor(method, "STUDENT_COURSES");
    for (const row of rows) manifest.push({ kind: "PHASE2_COURSE", ref: ref(method, policy, `student-course:${row.student_course_id}`, row.student_course_id, "STUDENT_RAW_ACADEMIC_HISTORY", "LIMITING_CONTEXT"), exposedFields: ["COURSE_CODE", "COURSE_TITLE", "COURSE_STATUS", "TERM"], courseCode: row.course_code, courseTitle: row.course_title, courseStatus: row.course_status, term: row.term });
  }

  if (request.evidence.studentMappingIds.length > 0) {
    const rows = await database.select<StudentMappingRow>("student_record_concept_mappings", { select: "*", profile_version_id: `eq.${request.profileVersionId}`, student_mapping_id: postgresIn(request.evidence.studentMappingIds) });
    if (rows.length !== request.evidence.studentMappingIds.length) throw new FitAdapterError("A selected student mapping is outside the profile", 422);
    const method = contract.methods.ACADEMIC;
    const policy = policyFor(method, "STUDENT_MAPPINGS");
    for (const row of rows) {
      if (row.mapping_status !== "VERIFIED" || row.retired_at !== null || row.reviewed_at === null || row.student_evidence_id === null) throw new FitAdapterError("Student mapping is not active and VERIFIED", 422);
      manifest.push({ kind: "VERIFIED_MAPPING", ref: ref(method, policy, `student-mapping:${row.student_mapping_id}`, row.student_record_id, "TAXONOMY_MAPPING", "AUTHORITATIVE"), mappingKind: "PHASE2_STUDENT", relationRegistryId: "STUDENT_COURSE_EQUIVALENCY", relation: "STUDENT_COURSE_EQUIVALENCY", conceptId: row.concept_id, statusAtPin: "VERIFIED", reviewedAtAtPin: row.reviewed_at, verificationEvidenceIdAtPin: row.student_evidence_id, retiredAtAtPin: null });
    }
  }

  const [programCourses, programCosts] = await Promise.all([
    database.select<{ course_id: string }>("program_courses", { select: "course_id", program_version_id: `eq.${request.programVersionId}`, retired_at: "is.null" }),
    database.select<ProgramCostRow>("program_costs", { select: "cost_id,program_version_id,currency,billing_basis", program_version_id: `eq.${request.programVersionId}`, retired_at: "is.null" }),
  ]);
  const normalizationRows = request.evidence.approvedFinancialNormalizationIds.length === 0 ? [] :
    await database.select<FinancialNormalizationRow>("fit_financial_normalizations", {
      select: "*",
      financial_normalization_id: postgresIn(request.evidence.approvedFinancialNormalizationIds),
    });
  const normalizationReviews = request.evidence.approvedFinancialNormalizationIds.length === 0 ? [] :
    await database.select<FinancialNormalizationReviewRow>("fit_financial_normalization_reviews_v014", {
      select: "*",
      financial_normalization_id: postgresIn(request.evidence.approvedFinancialNormalizationIds),
    });
  const normalizationPins = request.evidence.approvedFinancialNormalizationIds.length === 0 ? [] :
    await database.select<FinancialSourcePinRow>("fit_financial_source_pins_v014", { select: "*" });
  const normalizationInputs = request.evidence.approvedFinancialNormalizationIds.length === 0 ? [] :
    await database.select<FinancialConversionInputRow>("fit_financial_conversion_inputs_v014", { select: "*" });
  if (normalizationRows.length !== request.evidence.approvedFinancialNormalizationIds.length ||
      normalizationReviews.length !== normalizationRows.length || normalizationPins.length !== normalizationRows.length) {
    throw new FitAdapterError("Approved Financial normalization snapshot is incomplete", 422);
  }
  const allowedProgramRecords = new Set([request.programVersionId, ...programCourses.map((row) => row.course_id), ...programCosts.map((row) => row.cost_id)]);
  const directObservationIds = new Set(request.evidence.directFinancialComparisons.flatMap((row) => [row.amountObservationId, row.billingBasisObservationId]));
  const normalizedObservationIds = normalizationRows.flatMap((row) => {
    const pin = normalizationPins.find((candidate) => candidate.evaluation_id === row.evaluation_id && candidate.amount_observation_id === row.field_observation_id);
    return pin === undefined ? [row.field_observation_id] : [row.field_observation_id, pin.billing_basis_observation_id];
  });
  const requestedObservationIds = [...new Set([...request.evidence.canonicalObservationIds, ...directObservationIds, ...normalizedObservationIds])];
  const observations = requestedObservationIds.length === 0 ? [] : await database.select<ObservationRow>("field_observations", { select: "observation_id,record_type,record_id,field_name,observed_value,knowledge_status", observation_id: postgresIn(requestedObservationIds) });
  const selections = requestedObservationIds.length === 0 ? [] : await database.select<CanonicalSelectionRow>("canonical_field_selections", { select: "observation_id,record_type,record_id,field_name", observation_id: postgresIn(requestedObservationIds) });
  if (observations.length !== requestedObservationIds.length || selections.length !== requestedObservationIds.length || observations.some((row) => row.knowledge_status !== "KNOWN" || !allowedProgramRecords.has(row.record_id))) {
    throw new FitAdapterError("Canonical observations must be current KNOWN facts for the selected program", 422);
  }
  // A direct comparable itself satisfies PROGRAM_COSTS. A reviewed
  // normalization, however, is authorized by FINANCIAL_NORMALIZATIONS and
  // must retain its pinned amount/billing-basis observations as the exact
  // PROGRAM_COSTS witnesses. Those two witnesses are therefore materialized
  // as ordinary canonical facts and later rebound to the manifest rows that
  // the preparation transaction already pinned.
  const financialWitnessOnly = directObservationIds;
  for (const row of observations.filter((observation) => !financialWitnessOnly.has(observation.observation_id))) {
    for (const dimension of FIT_DIMENSIONS) {
      const method = contract.methods[dimension];
      const policy = method.inputPolicies.find((candidate) => candidate.disposition === "ALLOWED" && candidate.programFields.some((field) => field.recordType === row.record_type && field.fieldName === row.field_name));
      if (policy === undefined) continue;
      const sourceId = row.record_type === "PROGRAM_COURSE" ? row.record_id : row.observation_id;
      const duplicate = manifest.some((item) => item.ref.methodRegistryId === method.identity.id && item.kind === "CANONICAL_PROGRAM_FACT" && item.ref.sourceId === sourceId);
      if (duplicate) continue;
      manifest.push({ kind: "CANONICAL_PROGRAM_FACT", ref: ref(method, policy, `observation:${method.identity.id}:${row.observation_id}`, sourceId, "PROGRAM_CANONICAL_FACT", "AUTHORITATIVE"), recordId: row.record_id, knowledgeStatus: "KNOWN", selectedObservationId: row.observation_id, fact: programFact(row) });
    }
  }

  if (request.evidence.catalogMappingIds.length > 0) {
    const rows = await database.select<CatalogMappingRow>("catalog_concept_mappings", { select: "*", mapping_id: postgresIn(request.evidence.catalogMappingIds) });
    if (rows.length !== request.evidence.catalogMappingIds.length) throw new FitAdapterError("Unknown catalog mapping selection", 422);
    for (const row of rows) {
      if (!allowedProgramRecords.has(row.record_id) || row.mapping_status !== "VERIFIED" || row.retired_at !== null || row.reviewed_at === null || row.verification_evidence_id === null) throw new FitAdapterError("Catalog mapping is not an active VERIFIED mapping for the program", 422);
      for (const dimension of FIT_DIMENSIONS) {
        const method = contract.methods[dimension];
        if (!method.mappingRelations.some((relation) => relation.relationCode === row.relation)) continue;
        const candidatePolicies = method.inputPolicies.filter((policy) => policy.disposition === "ALLOWED" && policy.inputDomain === "CATALOG_MAPPINGS");
        if (candidatePolicies.length === 0) continue;
        const policy = dimension === "ACADEMIC"
          ? candidatePolicies.find((candidate) => candidate.fieldName === "ACADEMIC_MAPPING") ?? candidatePolicies[0]
          : candidatePolicies[0];
        if (policy === undefined) continue;
        if (manifest.some((item) => item.ref.methodRegistryId === method.identity.id && item.kind === "VERIFIED_MAPPING" && item.ref.sourceId === row.record_id)) continue;
        manifest.push({ kind: "VERIFIED_MAPPING", ref: ref(method, policy, `catalog-mapping:${method.identity.id}:${row.mapping_id}`, row.record_id, "TAXONOMY_MAPPING", "AUTHORITATIVE"), mappingKind: "CATALOG", relationRegistryId: row.relation, relation: row.relation as Extract<DecisionManifestItem, { kind: "VERIFIED_MAPPING" }>["relation"], conceptId: row.concept_id, statusAtPin: "VERIFIED", reviewedAtAtPin: row.reviewed_at, verificationEvidenceIdAtPin: row.verification_evidence_id, retiredAtAtPin: null });
      }
    }
  }

  if (request.evidence.taxonomyConceptIds.length > 0) {
    const [concepts, releases] = await Promise.all([
      database.select<TaxonomyConceptRow>("taxonomy_concepts", { select: "concept_id,introduced_in_release,retired_in_release", concept_id: postgresIn(request.evidence.taxonomyConceptIds) }),
      database.select<TaxonomyReleaseRow>("taxonomy_releases", { select: "release_code,release_ordinal" }),
    ]);
    if (concepts.length !== request.evidence.taxonomyConceptIds.length) throw new FitAdapterError("Unknown taxonomy concept selection", 422);
    const ordinal = new Map(releases.map((row) => [row.release_code, Number(row.release_ordinal)]));
    const pinned = ordinal.get(request.taxonomyReleaseCode);
    if (pinned === undefined) throw new FitAdapterError("Unknown taxonomy release", 422);
    for (const concept of concepts) {
      if ((ordinal.get(concept.introduced_in_release) ?? Infinity) > pinned || (concept.retired_in_release !== null && (ordinal.get(concept.retired_in_release) ?? -Infinity) <= pinned)) throw new FitAdapterError("Taxonomy concept is inactive in the pinned release", 422);
      for (const dimension of ["ACADEMIC", "CAREER", "INTERNATIONAL_ACCESSIBILITY"] as const) {
        const method = contract.methods[dimension];
        const policy = method.inputPolicies.find((candidate) => candidate.disposition === "ALLOWED" && candidate.inputDomain === "TAXONOMY_CONCEPTS");
        if (policy === undefined) continue;
        manifest.push({ kind: "TAXONOMY_CONCEPT", ref: ref(method, policy, `concept:${method.identity.id}:${concept.concept_id}`, concept.concept_id, "TAXONOMY_MAPPING", "LIMITING_CONTEXT"), conceptId: concept.concept_id, activeInPinnedRelease: true });
      }
    }
  }

  if (request.evidence.contextClaimIds.length > 0) {
    const claims = await database.select<ContextClaimRow>("fit_context_claims", { select: "*", context_claim_id: postgresIn(request.evidence.contextClaimIds) });
    const definitions = await database.select<ContextDefinitionRow>("fit_context_claim_definitions", { select: "claim_definition_id,claim_code,semantic_source_class_code" });
    const selectionsRows = await database.select<ContextSelectionRow>("fit_context_claim_selections", { select: "*", context_claim_id: postgresIn(request.evidence.contextClaimIds) });
    const observationIds = selectionsRows.flatMap((row) => row.context_observation_id === null ? [] : [row.context_observation_id]);
    const contextObservations = observationIds.length === 0 ? [] : await database.select<ContextObservationRow>("fit_context_claim_observations", { select: "*", context_observation_id: postgresIn(observationIds) });
    if (claims.length !== request.evidence.contextClaimIds.length || selectionsRows.length !== claims.length) throw new FitAdapterError("Context claims require exact current selections", 422);
    for (const claim of claims) {
      if (claim.program_version_id !== null && claim.program_version_id !== request.programVersionId) throw new FitAdapterError("Context claim belongs to another program", 422);
      const definition = requireOne(definitions.filter((row) => row.claim_definition_id === claim.claim_definition_id), "context definition");
      const selection = requireOne(selectionsRows.filter((row) => row.context_claim_id === claim.context_claim_id), "context selection");
      const observation = selection.context_observation_id === null ? null : requireOne(contextObservations.filter((row) => row.context_observation_id === selection.context_observation_id), "context observation");
      const dimension = definition.claim_code === "REVIEWED_CAREER_OUTCOME" ? "CAREER" as const : "INTERNATIONAL_ACCESSIBILITY" as const;
      const method = contract.methods[dimension];
      const policy = policyFor(method, "FIT_CONTEXT_CLAIMS");
      manifest.push({
        kind: "HISTORICAL_CONTEXT_SELECTION",
        ref: ref(method, policy, `context-claim:${method.identity.id}:${claim.context_claim_id}`, claim.context_claim_id, definition.semantic_source_class_code as ManifestRef["sourceClass"], observation === null ? "LIMITING_CONTEXT" : "AUTHORITATIVE"),
        claimId: claim.context_claim_id,
        selectionId: selection.context_selection_id,
        observationId: selection.context_observation_id,
        knowledgeStatus: selection.knowledge_status as Extract<DecisionManifestItem, { kind: "HISTORICAL_CONTEXT_SELECTION" }>["knowledgeStatus"],
        observationWorkflowStatusAtSelection: observation?.workflow_status === "VERIFIED" ? "VERIFIED" : null,
        observationReviewedAtAtSelection: observation?.reviewed_at ?? null,
        authority: observation?.authority as Extract<DecisionManifestItem, { kind: "HISTORICAL_CONTEXT_SELECTION" }>["authority"] ?? null,
        validFrom: isoDate(claim.valid_from),
        validTo: claim.valid_to === null ? null : isoDate(claim.valid_to),
        programVersionId: claim.program_version_id,
        geographyCode: claim.geography_code,
        jurisdictionCode: claim.jurisdiction_code,
        pathCode: claim.path_code,
        value: observation === null ? null : typedContextValue(definition.claim_code, observation.observed_value),
      });
    }
  }

  if (request.evidence.contextMappingIds.length > 0) {
    const rows = await database.select<ContextMappingRow>("fit_context_concept_mappings", { select: "*", context_mapping_id: postgresIn(request.evidence.contextMappingIds) });
    const claimIds = rows.map((row) => row.context_claim_id);
    const claims = claimIds.length === 0 ? [] : await database.select<ContextClaimRow>("fit_context_claims", { select: "*", context_claim_id: postgresIn(claimIds) });
    const definitions = await database.select<ContextDefinitionRow>("fit_context_claim_definitions", { select: "claim_definition_id,claim_code,semantic_source_class_code" });
    if (rows.length !== request.evidence.contextMappingIds.length) throw new FitAdapterError("Unknown context mapping selection", 422);
    for (const row of rows) {
      if (row.mapping_status !== "VERIFIED" || row.retired_at !== null || row.reviewed_at === null || row.verification_evidence_id === null) throw new FitAdapterError("Context mapping is not active and VERIFIED", 422);
      const claim = requireOne(claims.filter((candidate) => candidate.context_claim_id === row.context_claim_id), "context mapping claim");
      if (claim.program_version_id !== null && claim.program_version_id !== request.programVersionId) throw new FitAdapterError("Context mapping belongs to another program", 422);
      const definition = requireOne(definitions.filter((candidate) => candidate.claim_definition_id === claim.claim_definition_id), "context mapping definition");
      for (const dimension of FIT_DIMENSIONS) {
        const method = contract.methods[dimension];
        if (!method.mappingRelations.some((relation) => relation.relationCode === row.relation_code)) continue;
        const policy = method.inputPolicies.find((candidate) => candidate.disposition === "ALLOWED" && candidate.inputDomain === "FIT_CONTEXT_CLAIMS");
        if (policy === undefined) continue;
        manifest.push({ kind: "VERIFIED_MAPPING", ref: ref(method, policy, `context-mapping:${method.identity.id}:${row.context_mapping_id}`, row.context_claim_id, definition.semantic_source_class_code as ManifestRef["sourceClass"], "AUTHORITATIVE"), mappingKind: "FIT_CONTEXT", relationRegistryId: row.relation_code, relation: row.relation_code as Extract<DecisionManifestItem, { kind: "VERIFIED_MAPPING" }>["relation"], conceptId: row.concept_id, statusAtPin: "VERIFIED", reviewedAtAtPin: row.reviewed_at, verificationEvidenceIdAtPin: row.verification_evidence_id, retiredAtAtPin: null });
      }
    }
  }

  if (request.evidence.accessContextId !== null) {
    const access = await database.rpc<AccessContextRow>("get_fit_student_access_context_v016", { p_profile_version_id: request.profileVersionId, p_access_context_id: request.evidence.accessContextId });
    const method = contract.methods.INTERNATIONAL_ACCESSIBILITY;
    const policy = policyFor(method, "FIT_ACCESS_CONTEXT");
    manifest.push({ kind: "STUDENT_ACCESS_CONTEXT", ref: ref(method, policy, `access:${access.access_context_id}`, access.access_context_id, "STUDENT_RAW_ACCESS_CONTEXT", "AUTHORITATIVE"), citizenshipCountryCode: access.citizenship_country_code, residenceCountryCode: access.residence_country_code, jurisdictionCode: access.jurisdiction_code, currentStatusCode: access.current_status_code, authorizationPathCode: access.authorization_path_code, targetPathCode: access.target_path_code });
  }

  for (const selection of request.evidence.directFinancialComparisons) {
    const intent = intentById.get(selection.financialIntentId);
    if (intent === undefined || intent.kind !== "FINANCIAL_CONSTRAINT" || intent.semantics === "AVAILABLE_FUNDING") throw new FitAdapterError("Direct Financial selection requires a frozen cost constraint", 422);
    const amount = requireOne(observations.filter((row) => row.observation_id === selection.amountObservationId), "direct amount observation");
    const basis = requireOne(observations.filter((row) => row.observation_id === selection.billingBasisObservationId), "direct billing-basis observation");
    const cost = requireOne(programCosts.filter((row) => row.cost_id === amount.record_id), "direct program cost");
    const method = contract.methods.FINANCIAL;
    const policy = policyFor(method, "PROGRAM_COSTS");
    const semanticSource = `financial-source:${selection.amountObservationId}:${selection.billingBasisObservationId}`;
    manifest.push({ kind: "DIRECT_FINANCIAL_COMPARABLE", ref: ref(method, policy, `direct-financial:${selection.financialIntentId}`, `${amount.record_id}:${selection.financialIntentId}`, "PROGRAM_CANONICAL_FACT", "AUTHORITATIVE"), sourcePinId: semanticSource, financialContractVersion: "FINANCIAL_BILLING_BASIS_V014", financialConstraintIntentId: selection.financialIntentId, comparable: directComparable(selection, amount, basis, cost, intent) });
  }

  for (const row of normalizationRows) {
    if (row.profile_version_id !== request.profileVersionId || row.intent_set_id !== request.intentSetId) {
      throw new FitAdapterError("Financial normalization belongs to another frozen request", 422);
    }
    const review = requireOne(normalizationReviews.filter((candidate) => candidate.financial_normalization_id === row.financial_normalization_id), "normalization review");
    if (review.status !== "VERIFIED" || review.verification_evidence_id === null || review.retired_at !== null) {
      throw new FitAdapterError("Financial normalization is not active and VERIFIED", 422);
    }
    const intent = intentById.get(row.financial_constraint_id);
    if (intent === undefined || intent.kind !== "FINANCIAL_CONSTRAINT" || intent.semantics === "AVAILABLE_FUNDING") {
      throw new FitAdapterError("Financial normalization target is not a frozen cost constraint", 422);
    }
    const registered = requireOne(contract.financialNormalizations.filter((candidate) => candidate.identity.id === row.normalization_method_id), "registered Financial normalization method");
    const inputs = normalizationInputs.filter((candidate) => candidate.financial_normalization_id === row.financial_normalization_id);
    const sourceInput = requireOne(inputs.filter((candidate) => candidate.input_role === "SOURCE_AMOUNT"), "normalization source input");
    const yearsInput = requireOne(inputs.filter((candidate) => candidate.input_role === "ACADEMIC_YEARS"), "normalization academic-years input");
    const roundingInput = requireOne(inputs.filter((candidate) => candidate.input_role === "ROUNDING"), "normalization rounding input");
    const fundingInputs = inputs.filter((candidate) => candidate.input_role === "AVAILABLE_FUNDING");
    const methodContract = JSON.parse(registered.normalizationContractCanonicalJson) as Record<string, unknown>;
    const computedAmount = calculateReviewedFinancialNormalization({
      formulaCode: String(methodContract.formulaCode ?? ""),
      sourceAmount: decimal(sourceInput.numeric_value, "normalization source input"),
      academicYears: decimal(yearsInput.numeric_value, "normalization academic years"),
      fundingAmount: fundingInputs.length === 0 ? null : decimal(requireOne(fundingInputs, "normalization funding input").numeric_value, "normalization funding"),
      rounding: roundingInput.text_value ?? "",
      sourceCurrency: row.original_currency,
      targetCurrency: row.target_currency,
    });
    if (!equalExactDecimals(
      decimal(sourceInput.numeric_value, "normalization source input"),
      decimal(row.original_amount, "normalization original amount"),
    )) {
      throw new FitAdapterError("Reviewed Financial normalization source amount drift", 422);
    }
    const method = contract.methods.FINANCIAL;
    const policy = policyFor(method, "FINANCIAL_NORMALIZATIONS");
    manifest.push({
      kind: "APPROVED_FINANCIAL_NORMALIZATION",
      ref: ref(method, policy, `normalized-financial:${row.financial_constraint_id}`, row.financial_normalization_id, "FIT_CONTEXT_FINANCIAL", "AUTHORITATIVE"),
      normalizationId: row.normalization_method_id,
      fieldObservationId: row.field_observation_id,
      financialConstraintIntentId: row.financial_constraint_id,
      intentSetId: row.intent_set_id,
      financialContractVersion: "FINANCIAL_BILLING_BASIS_V014",
      methodCode: registered.identity.code,
      methodVersion: Number(registered.identity.version),
      verificationEvidenceId: review.verification_evidence_id,
      source: {
        amount: decimal(row.original_amount, "normalization original amount"),
        currency: row.original_currency.trim(),
        period: row.original_period,
        scope: row.original_scope,
        basis: row.original_basis,
        components: row.original_components,
      },
      target: {
        amount: computedAmount,
        currency: row.target_currency.trim(),
        period: row.target_period,
        scope: row.target_scope,
        basis: row.target_basis,
        components: row.target_components,
      },
      conversionEvidenceId: row.conversion_evidence_id,
    });
  }

  const inputStates = FIT_DIMENSIONS.flatMap((dimension) => {
    const method = contract.methods[dimension];
    const methodManifest = manifest.filter((item) => item.ref.methodRegistryId === method.identity.id);
    if (methodManifest.length === 0) throw new FitAdapterError(`${dimension} has no exact intent or provenance manifest`, 422);
    return method.inputPolicies.filter((policy) => policy.disposition === "ALLOWED").map((policy) => {
      const keys = methodManifest.filter((item) => item.ref.inputPolicyRegistryId === policy.identity.id).map((item) => item.ref.manifestItemKey);
      const included = keys.length > 0;
      return {
        methodRegistryId: method.identity.id,
        inputPolicyRegistryId: policy.identity.id,
        methodCode: methodCodeByDimension[dimension],
        policyKey: policy.policyKey as FitInputPolicyKey,
        requirement: policy.requirement,
        availability: included ? "INCLUDED" as const : "NOT_SUPPLIED" as const,
        manifestItemKeys: keys,
        completenessManifestItemKey: null,
        provenanceManifestItemKey: included ? null : methodManifest[0]!.ref.manifestItemKey,
      };
    });
  });

  return {
    schemaVersion: "fit-v0.1",
    contractRelease: { registryId: contract.release.id, releaseCode: "fit-v0.1", specificationVersion: "v0.1", digest: contract.release.specificationDigest },
    resolvedContract: contract,
    evaluator: { registryId: contract.evaluatorBuild.id, name: contract.evaluatorBuild.evaluatorName, version: contract.evaluatorBuild.evaluatorVersion, buildHash: contract.evaluatorBuild.buildHash },
    evaluationAsOf,
    profile: { versionId: profile.profile_version_id, snapshotHash: profile.snapshot_hash },
    intentSet: { id: intentSet.intent_set_id, snapshotHash: intentSet.snapshot_hash },
    programVersionId: request.programVersionId,
    taxonomyReleaseCode: request.taxonomyReleaseCode,
    methods: {
      ACADEMIC: { registryId: contract.methods.ACADEMIC.identity.id, methodCode: "ACADEMIC_ALIGNMENT_V01", methodVersion: 1, inferenceCategory: "HYBRID", permitsStrongAlignment: true },
      CAREER: { registryId: contract.methods.CAREER.identity.id, methodCode: "CAREER_ALIGNMENT_V01", methodVersion: 1, inferenceCategory: "HYBRID", permitsStrongAlignment: false },
      FINANCIAL: { registryId: contract.methods.FINANCIAL.identity.id, methodCode: "FINANCIAL_ALIGNMENT_V01", methodVersion: 1, inferenceCategory: "DETERMINISTIC", permitsStrongAlignment: false },
      GEOGRAPHIC_DELIVERY: { registryId: contract.methods.GEOGRAPHIC_DELIVERY.identity.id, methodCode: "GEOGRAPHIC_DELIVERY_ALIGNMENT_V01", methodVersion: 1, inferenceCategory: "HYBRID", permitsStrongAlignment: false },
      PERSONAL_PREFERENCE: { registryId: contract.methods.PERSONAL_PREFERENCE.identity.id, methodCode: "PERSONAL_PREFERENCE_ALIGNMENT_V01", methodVersion: 1, inferenceCategory: "HYBRID", permitsStrongAlignment: false },
      INTERNATIONAL_ACCESSIBILITY: { registryId: contract.methods.INTERNATIONAL_ACCESSIBILITY.identity.id, methodCode: "INTERNATIONAL_ACCESSIBILITY_V01", methodVersion: 1, inferenceCategory: "HYBRID", permitsStrongAlignment: false },
    },
    manifest,
    inputStates,
  };
}
