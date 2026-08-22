import {
  canonicalJson,
  FIT_DIMENSIONS,
  type FitAssessment,
  type FitDimension,
  type FitInputPolicyKey,
  type InferenceCategory,
  type ResolvedFitContract,
  type ResolvedMethodContract,
} from "@education-platform/fit-engine";
import { FitAdapterError, type FitDatabaseGateway, requireOne } from "./database-gateway.js";

type ReleaseRow = {
  contract_release_id: string;
  release_code: string;
  specification_version: string;
  upstream_contract_version: string;
  specification_digest: string;
  status: string;
  reviewed_by: string | null;
  reviewed_at: string | null;
  retired_at: string | null;
  retirement_reason: string | null;
};
type BuildRow = {
  evaluator_build_id: string;
  contract_release_id: string;
  evaluator_name: string;
  evaluator_version: string;
  build_hash: string;
  status: string;
  reviewed_by: string | null;
  reviewed_at: string | null;
  verification_evidence_id: string | null;
  retired_at: string | null;
  retirement_reason: string | null;
};
type MethodRow = {
  method_id: string;
  contract_release_id: string;
  dimension: FitDimension;
  method_code: string;
  method_version: number;
  status: string;
  inference_category: InferenceCategory;
  materiality_contract: unknown;
  permits_strong_alignment: boolean;
  reviewed_by: string | null;
  reviewed_at: string | null;
  verification_evidence_id: string | null;
  retired_at: string | null;
  retirement_reason: string | null;
};
type SourceClassRow = {
  source_class_code: string;
  owner_layer: "PHASE1" | "PHASE2" | "PHASE3" | "PROHIBITED";
  fit_permitted: boolean;
  description: string;
};
type SourcePolicyRow = {
  method_id: string;
  source_class_code: string;
  disposition: "ALLOWED" | "FORBIDDEN";
};
type InputPolicyRow = {
  input_policy_id: string;
  method_id: string;
  input_domain: string;
  field_name: string;
  disposition: "ALLOWED" | "FORBIDDEN";
  requirement: "REQUIRED" | "OPTIONAL";
  acceptable_authority: string | null;
  acceptable_claim_status: string | null;
  permits_deterministic_use: boolean;
  permits_model_use: boolean;
};
type ProgramFieldRow = {
  method_id: string;
  input_policy_id: string;
  record_type: string;
  field_name: string;
};
type RelationDefinitionRow = {
  relation_code: string;
  relation_domain: "CATALOG" | "STUDENT" | "FIT_CONTEXT";
  description: string;
};
type RelationPolicyRow = {
  method_id: string;
  relation_code: string;
  allowed_assessments: FitAssessment[];
  permits_strong_alignment: boolean;
};
type SignalTypeRow = {
  signal_type_id: string;
  method_id: string;
  signal_code: string;
  direction: "SUPPORTING" | "CONTRADICTING" | "LIMITING";
  material: boolean;
  allowed_inference_categories: InferenceCategory[];
  permits_strong_alignment: boolean;
  description: string;
};
type ReasonRow = {
  reason_definition_id: string;
  contract_release_id: string;
  reason_code: string;
  dimension: FitDimension | null;
  reason_family: string;
  direction: "SUPPORTING" | "CONTRADICTING" | "LIMITING";
  allowed_assessments: FitAssessment[];
  description: string;
  status: string;
  reviewed_by: string | null;
  reviewed_at: string | null;
  retired_at: string | null;
  retirement_reason: string | null;
};
type NormalizationRow = {
  normalization_method_id: string;
  contract_release_id: string;
  method_code: string;
  method_version: number;
  status: string;
  source_scope: "COMPONENT" | "PARTIAL_TOTAL" | "TOTAL_COST";
  target_scope: "COMPONENT" | "PARTIAL_TOTAL" | "TOTAL_COST";
  source_period: "MONTH" | "ACADEMIC_YEAR" | "CALENDAR_YEAR" | "PROGRAM_DURATION";
  target_period: "MONTH" | "ACADEMIC_YEAR" | "CALENDAR_YEAR" | "PROGRAM_DURATION";
  source_basis: "GROSS" | "NET_OF_VERIFIED_FUNDING";
  target_basis: "GROSS" | "NET_OF_VERIFIED_FUNDING";
  source_currency: string | null;
  target_currency: string | null;
  normalization_contract: unknown;
  reviewed_by: string | null;
  reviewed_at: string | null;
  verification_evidence_id: string | null;
  retired_at: string | null;
  retirement_reason: string | null;
};

function requireReviewed(row: {
  status: string;
  reviewed_by: string | null;
  reviewed_at: string | null;
  retired_at: string | null;
  retirement_reason: string | null;
}, label: string) {
  if (row.status !== "VERIFIED" || row.reviewed_by === null || row.reviewed_at === null || row.retired_at !== null) {
    throw new FitAdapterError(`${label} is not active and VERIFIED`, 409);
  }
  return {
    status: "VERIFIED" as const,
    reviewedBy: row.reviewed_by,
    reviewedAt: row.reviewed_at,
    retiredAt: null,
    retirementReason: null,
  };
}

function requireVerifiedArtifact(row: Parameters<typeof requireReviewed>[0] & {
  verification_evidence_id: string | null;
}, label: string) {
  if (row.verification_evidence_id === null) {
    throw new FitAdapterError(`${label} has no verification evidence`, 409);
  }
  return {
    ...requireReviewed(row, label),
    verificationEvidenceId: row.verification_evidence_id,
  };
}

export type ResolveRegistryOptions = Readonly<{
  evaluatorName: string;
  evaluatorVersion: string;
}>;

export async function resolveFitContract(
  database: FitDatabaseGateway,
  options: ResolveRegistryOptions,
): Promise<ResolvedFitContract> {
  const release = requireOne(await database.select<ReleaseRow>("fit_contract_releases", {
    select: "*",
    release_code: "eq.fit-v0.1",
    status: "eq.VERIFIED",
    retired_at: "is.null",
  }), "fit-v0.1 release");
  const build = requireOne(await database.select<BuildRow>("fit_evaluator_builds", {
    select: "*",
    contract_release_id: `eq.${release.contract_release_id}`,
    evaluator_name: `eq.${options.evaluatorName}`,
    evaluator_version: `eq.${options.evaluatorVersion}`,
    status: "eq.VERIFIED",
    retired_at: "is.null",
  }), "production evaluator build");

  const [
    methodRows,
    sourceClasses,
    sourcePolicies,
    inputPolicies,
    programFields,
    relationDefinitions,
    relationPolicies,
    signalTypes,
    reasons,
    normalizations,
  ] = await Promise.all([
    database.select<MethodRow>("fit_dimension_methods", { select: "*", contract_release_id: `eq.${release.contract_release_id}` }),
    database.select<SourceClassRow>("fit_semantic_source_classes", { select: "*" }),
    database.select<SourcePolicyRow>("fit_method_source_class_policies", { select: "*" }),
    database.select<InputPolicyRow>("fit_method_input_policies", { select: "*" }),
    database.select<ProgramFieldRow>("fit_method_program_field_policies", { select: "*" }),
    database.select<RelationDefinitionRow>("fit_mapping_relation_definitions", { select: "*" }),
    database.select<RelationPolicyRow>("fit_method_mapping_relation_policies", { select: "*" }),
    database.select<SignalTypeRow>("fit_signal_types", { select: "*" }),
    database.select<ReasonRow>("fit_reason_definitions", { select: "*", contract_release_id: `eq.${release.contract_release_id}` }),
    database.select<NormalizationRow>("fit_financial_normalization_methods", { select: "*", contract_release_id: `eq.${release.contract_release_id}` }),
  ]);

  const verifiedMethods = methodRows.filter((row) => row.status === "VERIFIED" && row.retired_at === null);
  if (verifiedMethods.length !== FIT_DIMENSIONS.length) {
    throw new FitAdapterError("fit-v0.1 requires exactly six active VERIFIED methods", 409, {
      count: verifiedMethods.length,
    });
  }
  const methods = Object.fromEntries(FIT_DIMENSIONS.map((dimension) => {
    const row = requireOne(verifiedMethods.filter((method) => method.dimension === dimension), `${dimension} method`);
    const method: ResolvedMethodContract = {
      identity: { id: row.method_id, code: row.method_code, version: String(row.method_version) },
      dimension,
      inferenceCategory: row.inference_category,
      permitsStrongAlignment: row.permits_strong_alignment,
      materialityContractCanonicalJson: canonicalJson(row.materiality_contract),
      definitionState: requireVerifiedArtifact(row, `${dimension} method`),
      sourceClassPolicies: sourcePolicies
        .filter((policy) => policy.method_id === row.method_id)
        .map((policy) => ({
          methodRegistryId: row.method_id,
          sourceClassRegistryId: policy.source_class_code,
          sourceClassCode: policy.source_class_code,
          disposition: policy.disposition,
        })),
      inputPolicies: inputPolicies
        .filter((policy) => policy.method_id === row.method_id)
        .map((policy) => {
          const policyKey = `${row.method_code}/${policy.input_domain}/${policy.field_name}` as FitInputPolicyKey;
          return {
            identity: { id: policy.input_policy_id, code: policyKey, version: "1" },
            methodRegistryId: row.method_id,
            policyKey,
            inputDomain: policy.input_domain,
            fieldName: policy.field_name,
            disposition: policy.disposition,
            requirement: policy.requirement,
            acceptableAuthority: policy.acceptable_authority,
            acceptableClaimStatus: policy.acceptable_claim_status,
            programFields: programFields
              .filter((field) => field.method_id === row.method_id && field.input_policy_id === policy.input_policy_id)
              .map((field) => ({
                methodRegistryId: row.method_id,
                inputPolicyRegistryId: policy.input_policy_id,
                recordType: field.record_type,
                fieldName: field.field_name,
              })),
            permitsDeterministicUse: policy.permits_deterministic_use,
            permitsModelUse: policy.permits_model_use,
          };
        }),
      mappingRelations: relationPolicies
        .filter((policy) => policy.method_id === row.method_id)
        .map((policy) => ({
          methodRegistryId: row.method_id,
          relationRegistryId: policy.relation_code,
          relationCode: policy.relation_code,
          allowedAssessments: policy.allowed_assessments,
          permitsStrongAlignment: policy.permits_strong_alignment,
        })),
      signalTypes: signalTypes
        .filter((signal) => signal.method_id === row.method_id)
        .map((signal) => ({
          identity: { id: signal.signal_type_id, code: signal.signal_code, version: "1" },
          methodRegistryId: row.method_id,
          direction: signal.direction,
          material: signal.material,
          allowedInferenceCategories: signal.allowed_inference_categories,
          permitsStrongAlignment: signal.permits_strong_alignment,
          description: signal.description,
        })),
    };
    return [dimension, method];
  })) as unknown as ResolvedFitContract["methods"];

  return {
    release: {
      id: release.contract_release_id,
      code: "fit-v0.1",
      version: "v0.1",
      specificationDigest: release.specification_digest,
      upstreamContractVersion: "phase2-eligibility-v0.1",
      definitionState: requireReviewed(release, "fit-v0.1 release"),
    },
    evaluatorBuild: {
      id: build.evaluator_build_id,
      code: build.evaluator_name,
      version: build.evaluator_version,
      evaluatorName: build.evaluator_name,
      evaluatorVersion: build.evaluator_version,
      buildHash: build.build_hash,
      definitionState: requireVerifiedArtifact(build, "production evaluator build"),
    },
    semanticSourceClasses: sourceClasses.map((row) => ({
      sourceClassRegistryId: row.source_class_code,
      sourceClassCode: row.source_class_code,
      ownerLayer: row.owner_layer,
      fitPermitted: row.fit_permitted,
      description: row.description,
    })),
    mappingRelationDefinitions: relationDefinitions.map((row) => ({
      relationRegistryId: row.relation_code,
      relationCode: row.relation_code,
      relationDomain: row.relation_domain,
      description: row.description,
    })),
    methods,
    reasons: reasons
      .filter((row) => row.status === "VERIFIED" && row.retired_at === null)
      .map((row) => ({
        identity: { id: row.reason_definition_id, code: row.reason_code, version: "1" },
        contractReleaseRegistryId: row.contract_release_id,
        dimension: row.dimension,
        reasonFamily: row.reason_family,
        direction: row.direction,
        allowedAssessments: row.allowed_assessments,
        description: row.description,
        definitionState: requireReviewed(row, `reason ${row.reason_code}`),
      })),
    financialNormalizations: normalizations
      .filter((row) => row.status === "VERIFIED" && row.retired_at === null)
      .map((row) => ({
        identity: { id: row.normalization_method_id, code: row.method_code, version: String(row.method_version) },
        contractReleaseRegistryId: row.contract_release_id,
        sourceScope: row.source_scope,
        targetScope: row.target_scope,
        sourcePeriod: row.source_period,
        targetPeriod: row.target_period,
        sourceBasis: row.source_basis,
        targetBasis: row.target_basis,
        sourceCurrency: row.source_currency?.trim() ?? null,
        targetCurrency: row.target_currency?.trim() ?? null,
        normalizationContractCanonicalJson: canonicalJson(row.normalization_contract),
        definitionState: requireVerifiedArtifact(row, `normalization ${row.method_code}`),
      })),
  };
}
