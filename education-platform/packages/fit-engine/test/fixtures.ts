import {
  FIT_DIMENSIONS,
  type DecisionManifestItem,
  type FitAssessment,
  type FitDimension,
  type FitEvaluationInput,
  type FitInputPolicyKey,
  type FitInputState,
  type FitMethodCode,
  type FitReasonCode,
  type InferenceCategory,
  type ManifestRef,
  type ResolvedFitContract,
  type SourceClass,
} from "../src/index.js";

const releaseId = "release-fit-v01";
const reviewedAt = "2026-08-20T00:00:00.000Z";
const review = {
  status: "VERIFIED" as const,
  reviewedBy: "fixture-review",
  reviewedAt,
  retiredAt: null,
  retirementReason: null,
};
const verified = { ...review, verificationEvidenceId: "fixture-verification-evidence" };

const dimensionConfig: Readonly<
  Record<
    FitDimension,
    Readonly<{
      methodId: string;
      methodCode: FitMethodCode;
      inference: InferenceCategory;
      strong: boolean;
      intentPolicy: FitInputPolicyKey;
      evidencePolicies: readonly FitInputPolicyKey[];
      completenessPolicy: FitInputPolicyKey;
    }>
  >
> = {
  ACADEMIC: {
    methodId: "method-academic",
    methodCode: "ACADEMIC_ALIGNMENT_V01",
    inference: "HYBRID",
    strong: true,
    intentPolicy: "ACADEMIC_ALIGNMENT_V01/FIT_INTENTS/DECLARED_ACADEMIC_INTENT",
    evidencePolicies: [
      "ACADEMIC_ALIGNMENT_V01/PROGRAM_COURSES/CURRICULUM",
      "ACADEMIC_ALIGNMENT_V01/CATALOG_MAPPINGS/ACADEMIC_MAPPING",
    ],
    completenessPolicy: "ACADEMIC_ALIGNMENT_V01/STUDENT_COMPLETENESS/ACADEMIC_INPUT_AVAILABILITY",
  },
  CAREER: {
    methodId: "method-career",
    methodCode: "CAREER_ALIGNMENT_V01",
    inference: "HYBRID",
    strong: false,
    intentPolicy: "CAREER_ALIGNMENT_V01/FIT_INTENTS/DECLARED_CAREER_INTENT",
    evidencePolicies: ["CAREER_ALIGNMENT_V01/CATALOG_MAPPINGS/CAREER_MAPPING"],
    completenessPolicy: "CAREER_ALIGNMENT_V01/STUDENT_COMPLETENESS/CAREER_INPUT_AVAILABILITY",
  },
  FINANCIAL: {
    methodId: "method-financial",
    methodCode: "FINANCIAL_ALIGNMENT_V01",
    inference: "DETERMINISTIC",
    strong: false,
    intentPolicy: "FINANCIAL_ALIGNMENT_V01/FIT_INTENTS/DECLARED_FINANCIAL_INTENT",
    evidencePolicies: [
      "FINANCIAL_ALIGNMENT_V01/PROGRAM_COSTS/COST_COMPONENTS",
      "FINANCIAL_ALIGNMENT_V01/FINANCIAL_NORMALIZATIONS/COMPARABLE_FINANCIAL_ARTIFACT",
    ],
    completenessPolicy: "FINANCIAL_ALIGNMENT_V01/STUDENT_COMPLETENESS/FINANCIAL_INPUT_AVAILABILITY",
  },
  GEOGRAPHIC_DELIVERY: {
    methodId: "method-geographic",
    methodCode: "GEOGRAPHIC_DELIVERY_ALIGNMENT_V01",
    inference: "HYBRID",
    strong: false,
    intentPolicy: "GEOGRAPHIC_DELIVERY_ALIGNMENT_V01/FIT_INTENTS/DECLARED_GEOGRAPHIC_DELIVERY_INTENT",
    evidencePolicies: ["GEOGRAPHIC_DELIVERY_ALIGNMENT_V01/PROGRAM_VERSIONS/LOCATION_DELIVERY"],
    completenessPolicy: "GEOGRAPHIC_DELIVERY_ALIGNMENT_V01/STUDENT_COMPLETENESS/GEOGRAPHIC_DELIVERY_INPUT_AVAILABILITY",
  },
  PERSONAL_PREFERENCE: {
    methodId: "method-personal",
    methodCode: "PERSONAL_PREFERENCE_ALIGNMENT_V01",
    inference: "HYBRID",
    strong: false,
    intentPolicy: "PERSONAL_PREFERENCE_ALIGNMENT_V01/FIT_INTENTS/DECLARED_PERSONAL_PREFERENCE_INTENT",
    evidencePolicies: ["PERSONAL_PREFERENCE_ALIGNMENT_V01/PROGRAM_VERSIONS/OBSERVABLE_CHARACTERISTICS"],
    completenessPolicy: "PERSONAL_PREFERENCE_ALIGNMENT_V01/STUDENT_COMPLETENESS/PERSONAL_PREFERENCE_INPUT_AVAILABILITY",
  },
  INTERNATIONAL_ACCESSIBILITY: {
    methodId: "method-international",
    methodCode: "INTERNATIONAL_ACCESSIBILITY_V01",
    inference: "HYBRID",
    strong: false,
    intentPolicy: "INTERNATIONAL_ACCESSIBILITY_V01/FIT_INTENTS/DECLARED_INTERNATIONAL_PATH_INTENT",
    evidencePolicies: [
      "INTERNATIONAL_ACCESSIBILITY_V01/FIT_CONTEXT_CLAIMS/INTERNATIONAL_ACCESS_EVIDENCE",
      "INTERNATIONAL_ACCESSIBILITY_V01/FIT_ACCESS_CONTEXT/AUTHORIZED_STUDENT_ACCESS_CONTEXT",
      "INTERNATIONAL_ACCESSIBILITY_V01/TAXONOMY_CONCEPTS/INTERNATIONAL_PATH_CONCEPT",
    ],
    completenessPolicy: "INTERNATIONAL_ACCESSIBILITY_V01/STUDENT_COMPLETENESS/INTERNATIONAL_INPUT_AVAILABILITY",
  },
};

const sourceClasses: readonly SourceClass[] = [
  "PROGRAM_CANONICAL_FACT",
  "STUDENT_RAW_INTENT",
  "STUDENT_RAW_ACADEMIC_HISTORY",
  "STUDENT_RAW_ACCESS_CONTEXT",
  "TAXONOMY_MAPPING",
  "FIT_CONTEXT_REGULATORY",
  "FIT_CONTEXT_CAREER",
  "FIT_CONTEXT_FINANCIAL",
  "FIT_CONTEXT_ACCESSIBILITY",
];

const relationDefinitions = [
  "FIELD_CLASSIFICATION",
  "SUBFIELD_CLASSIFICATION",
  "SUBJECT_CLASSIFICATION",
  "COURSE_EQUIVALENCY",
  "SKILL_ASSOCIATION",
  "CAREER_ASSOCIATION",
  "INDUSTRY_ASSOCIATION",
  "STUDENT_COURSE_EQUIVALENCY",
  "PROGRAM_RELATED_TO_CAREER",
  "PROGRAM_ASSOCIATED_WITH_PATH",
  "CLAIM_APPLIES_TO_CONCEPT",
] as const;

const reasonSpecs: readonly Readonly<{
  code: FitReasonCode;
  direction: "SUPPORTING" | "CONTRADICTING" | "LIMITING";
  assessments: readonly FitAssessment[];
  dimension: FitDimension | null;
}>[] = [
  { code: "STUDENT_PREFERENCE_UNSPECIFIED", direction: "LIMITING", assessments: ["UNKNOWN"], dimension: null },
  { code: "REQUIRED_INPUT_UNAVAILABLE", direction: "LIMITING", assessments: ["UNKNOWN"], dimension: null },
  { code: "MATERIAL_EVIDENCE_SUPPORTS_ALIGNMENT", direction: "SUPPORTING", assessments: ["STRONG_ALIGNMENT", "ALIGNMENT", "MIXED"], dimension: null },
  { code: "MATERIAL_EVIDENCE_CONTRADICTS_INTENT", direction: "CONTRADICTING", assessments: ["MIXED", "MISALIGNMENT"], dimension: null },
  { code: "REQUIRED_CONSTRAINT_CONTRADICTED", direction: "CONTRADICTING", assessments: ["MISALIGNMENT"], dimension: null },
  { code: "MODEL_INFERENCE_LIMITATION", direction: "LIMITING", assessments: ["ALIGNMENT", "MIXED", "MISALIGNMENT", "UNKNOWN"], dimension: null },
  { code: "SOURCE_CONFLICT", direction: "LIMITING", assessments: ["UNKNOWN"], dimension: null },
  { code: "FINANCIAL_INPUTS_INCOMPARABLE", direction: "LIMITING", assessments: ["UNKNOWN"], dimension: "FINANCIAL" },
  { code: "INTERNATIONAL_EVIDENCE_INAPPLICABLE", direction: "LIMITING", assessments: ["UNKNOWN"], dimension: "INTERNATIONAL_ACCESSIBILITY" },
  { code: "STUDENT_INPUT_INCOMPLETE", direction: "LIMITING", assessments: ["UNKNOWN"], dimension: null },
  { code: "PROGRAM_FACT_UNKNOWN", direction: "LIMITING", assessments: ["UNKNOWN"], dimension: null },
  { code: "STALE_SOURCE", direction: "LIMITING", assessments: ["UNKNOWN"], dimension: null },
  { code: "NO_AUTHORITATIVE_MAPPING", direction: "LIMITING", assessments: ["UNKNOWN"], dimension: null },
  { code: "EVIDENCE_INSUFFICIENT", direction: "LIMITING", assessments: ["UNKNOWN"], dimension: null },
  { code: "METHOD_UNSUPPORTED", direction: "LIMITING", assessments: ["UNKNOWN"], dimension: null },
  { code: "INPUT_INAPPLICABLE", direction: "LIMITING", assessments: ["UNKNOWN"], dimension: null },
  { code: "INTENT_CONFLICT", direction: "LIMITING", assessments: ["UNKNOWN"], dimension: null },
];

function policyId(dimension: FitDimension, key: FitInputPolicyKey): string {
  return `policy-${dimension.toLowerCase()}-${key.split("/").at(-1)?.toLowerCase()}`;
}

function programFieldsFor(
  dimension: FitDimension,
  key: FitInputPolicyKey,
  methodRegistryId: string,
  inputPolicyRegistryId: string,
) {
  const fields: readonly Readonly<{ recordType: string; fieldName: string }>[] =
    key === "ACADEMIC_ALIGNMENT_V01/PROGRAM_COURSES/CURRICULUM"
      ? [
          { recordType: "PROGRAM_COURSE", fieldName: "course_name" },
          { recordType: "PROGRAM_COURSE", fieldName: "official_description" },
        ]
      : key === "FINANCIAL_ALIGNMENT_V01/PROGRAM_COSTS/COST_COMPONENTS"
        ? [
            { recordType: "PROGRAM_COST", fieldName: "tuition_amount" },
            { recordType: "PROGRAM_COST", fieldName: "mandatory_fees" },
            { recordType: "PROGRAM_COST", fieldName: "estimated_living_cost" },
            { recordType: "PROGRAM_COST", fieldName: "estimated_total_cost" },
            { recordType: "PROGRAM_COST", fieldName: "currency" },
            { recordType: "PROGRAM_COST", fieldName: "billing_basis" },
          ]
        : key === "GEOGRAPHIC_DELIVERY_ALIGNMENT_V01/PROGRAM_VERSIONS/LOCATION_DELIVERY"
          ? [{ recordType: "PROGRAM_VERSION", fieldName: "delivery_mode" }]
          : key === "PERSONAL_PREFERENCE_ALIGNMENT_V01/PROGRAM_VERSIONS/OBSERVABLE_CHARACTERISTICS"
            ? [
                { recordType: "PROGRAM_VERSION", fieldName: "duration_months" },
                { recordType: "PROGRAM_VERSION", fieldName: "full_time" },
                { recordType: "PROGRAM_VERSION", fieldName: "capstone_required" },
              ]
            : key === "INTERNATIONAL_ACCESSIBILITY_V01/PROGRAM_VERSIONS/INTERNATIONAL_PROGRAM_FACTS"
              ? [{ recordType: "PROGRAM_VERSION", fieldName: "stem_status" }]
              : [];
  return fields.map((field) => ({
    methodRegistryId,
    inputPolicyRegistryId,
    ...field,
  }));
}

export function methodId(dimension: FitDimension): string {
  return dimensionConfig[dimension].methodId;
}

export function policyRegistryId(dimension: FitDimension, key: FitInputPolicyKey): string {
  return policyId(dimension, key);
}

export function ref(
  dimension: FitDimension,
  policyKey: FitInputPolicyKey,
  manifestItemKey: string,
  sourceId: string,
  sourceClass: SourceClass,
): ManifestRef {
  const config = dimensionConfig[dimension];
  return {
    manifestItemKey,
    sourceId,
    methodRegistryId: config.methodId,
    inputPolicyRegistryId: policyId(dimension, policyKey),
    methodCode: config.methodCode,
    policyKey,
    sourceClass,
    authorityRole: "AUTHORITATIVE",
  };
}

function contract(): ResolvedFitContract {
  const methods = Object.fromEntries(
    FIT_DIMENSIONS.map((dimension) => {
      const config = dimensionConfig[dimension];
      const policyKeys = [
        config.intentPolicy,
        ...config.evidencePolicies,
        config.completenessPolicy,
      ];
      const signalCodes = [
        ["MATERIAL_SUPPORT", "SUPPORTING", true, false],
        ["MATERIAL_CONTRADICTION", "CONTRADICTING", true, false],
        ["NON_MATERIAL_SUPPORT", "SUPPORTING", false, false],
        ["NON_MATERIAL_CONTRADICTION", "CONTRADICTING", false, false],
        ["LIMITING_CONTEXT", "LIMITING", false, false],
        ["DIRECT_HIGH_IMPORTANCE_AUTHORITATIVE_MATCH", "SUPPORTING", true, dimension === "ACADEMIC"],
      ] as const;
      return [
        dimension,
        {
          identity: { id: config.methodId, code: config.methodCode, version: "1" },
          dimension,
          inferenceCategory: config.inference,
          permitsStrongAlignment: config.strong,
          materialityContractCanonicalJson: "{}",
          definitionState: verified,
          sourceClassPolicies: sourceClasses.map((sourceClass) => ({
            methodRegistryId: config.methodId,
            sourceClassRegistryId: sourceClass,
            sourceClassCode: sourceClass,
            disposition: "ALLOWED" as const,
          })),
          inputPolicies: policyKeys.map((key) => ({
            identity: { id: policyId(dimension, key), code: key, version: "1" },
            methodRegistryId: config.methodId,
            policyKey: key,
            inputDomain: key.split("/")[1] ?? "UNKNOWN",
            fieldName: key.split("/")[2] ?? "UNKNOWN",
            disposition: "ALLOWED" as const,
            requirement:
              key === config.completenessPolicy || config.evidencePolicies.indexOf(key) > 0
                ? "OPTIONAL" as const
                : "REQUIRED" as const,
            acceptableAuthority: null,
            acceptableClaimStatus: null,
            programFields: programFieldsFor(
              dimension,
              key,
              config.methodId,
              policyId(dimension, key),
            ),
            permitsDeterministicUse: true,
            permitsModelUse: config.inference !== "DETERMINISTIC",
          })),
          mappingRelations: relationDefinitions.map((relation) => ({
            methodRegistryId: config.methodId,
            relationRegistryId: relation,
            relationCode: relation,
            allowedAssessments: ["ALIGNMENT", "MIXED", "MISALIGNMENT", "UNKNOWN"] as const,
            permitsStrongAlignment: false,
          })),
          signalTypes: signalCodes.map(([code, direction, material, strong]) => ({
            identity: { id: `signal-${config.methodId}-${code}`, code, version: "1" },
            methodRegistryId: config.methodId,
            direction,
            material,
            allowedInferenceCategories:
              config.inference === "DETERMINISTIC"
                ? ["DETERMINISTIC" as const]
                : ["DETERMINISTIC", "REVIEWED_MAPPING", "RULE", "MODEL", "HYBRID"] as const,
            permitsStrongAlignment: strong,
            description: code,
          })),
        },
      ];
    }),
  ) as unknown as ResolvedFitContract["methods"];
  return {
    release: {
      id: releaseId,
      code: "fit-v0.1",
      version: "v0.1",
      specificationDigest: "d".repeat(64),
      upstreamContractVersion: "phase2-eligibility-v0.1",
      definitionState: review,
    },
    evaluatorBuild: {
      id: "fit-engine-fixture-build",
      code: "fit-engine-fixture",
      version: "0.1.0",
      evaluatorName: "fit-engine",
      evaluatorVersion: "0.1.0",
      buildHash: "b".repeat(64),
      definitionState: verified,
    },
    semanticSourceClasses: sourceClasses.map((sourceClass) => ({
      sourceClassRegistryId: sourceClass,
      sourceClassCode: sourceClass,
      ownerLayer: "PHASE3" as const,
      fitPermitted: true,
      description: sourceClass,
    })),
    mappingRelationDefinitions: relationDefinitions.map((relation) => ({
      relationRegistryId: relation,
      relationCode: relation,
      relationDomain: "FIT_CONTEXT" as const,
      description: relation,
    })),
    methods,
    reasons: reasonSpecs.map((spec, index) => ({
      identity: { id: `reason-${String(index + 1).padStart(2, "0")}`, code: spec.code, version: "1" },
      contractReleaseRegistryId: releaseId,
      dimension: spec.dimension,
      reasonFamily: spec.code,
      direction: spec.direction,
      allowedAssessments: spec.assessments,
      description: spec.code,
      definitionState: review,
    })),
    financialNormalizations: [],
  };
}

function completenessItem(dimension: FitDimension): DecisionManifestItem {
  const config = dimensionConfig[dimension];
  return {
    kind: "PHASE2_COMPLETENESS",
    ref: ref(
      dimension,
      config.completenessPolicy,
      `completeness-${dimension.toLowerCase()}`,
      `completeness-source-${dimension.toLowerCase()}`,
      "STUDENT_RAW_INTENT",
    ),
    educationContextId: null,
    domain: dimension,
    completeness: "UNKNOWN",
  };
}

export function unknownInput(): FitEvaluationInput {
  const manifest = FIT_DIMENSIONS.map(completenessItem);
  const states: FitInputState[] = [];
  for (const dimension of FIT_DIMENSIONS) {
    const config = dimensionConfig[dimension];
    const completenessKey = `completeness-${dimension.toLowerCase()}`;
    for (const key of [config.intentPolicy, ...config.evidencePolicies]) {
      const requirement =
        config.evidencePolicies.indexOf(key) > 0 ? "OPTIONAL" as const : "REQUIRED" as const;
      states.push({
        methodRegistryId: config.methodId,
        inputPolicyRegistryId: policyId(dimension, key),
        methodCode: config.methodCode,
        policyKey: key,
        requirement,
        availability: "NOT_SUPPLIED",
        manifestItemKeys: [],
        completenessManifestItemKey: completenessKey,
        provenanceManifestItemKey: null,
      });
    }
    states.push({
      methodRegistryId: config.methodId,
      inputPolicyRegistryId: policyId(dimension, config.completenessPolicy),
      methodCode: config.methodCode,
      policyKey: config.completenessPolicy,
      requirement: "OPTIONAL",
      availability: "INCLUDED",
      manifestItemKeys: [completenessKey],
      completenessManifestItemKey: null,
      provenanceManifestItemKey: null,
    });
  }
  return {
    schemaVersion: "fit-v0.1",
    contractRelease: {
      registryId: releaseId,
      releaseCode: "fit-v0.1",
      specificationVersion: "v0.1",
      digest: "d".repeat(64),
    },
    resolvedContract: contract(),
    evaluator: {
      registryId: "fit-engine-fixture-build",
      name: "fit-engine",
      version: "0.1.0",
      buildHash: "b".repeat(64),
    },
    evaluationAsOf: "2026-08-21T00:00:00.000Z",
    profile: { versionId: "profile-v1", snapshotHash: "p".repeat(64) },
    intentSet: { id: "intent-set-v1", snapshotHash: "i".repeat(64) },
    programVersionId: "program-version-v1",
    taxonomyReleaseCode: "taxonomy-v1",
    methods: {
      ACADEMIC: { registryId: methodId("ACADEMIC"), methodCode: "ACADEMIC_ALIGNMENT_V01", methodVersion: 1, inferenceCategory: "HYBRID", permitsStrongAlignment: true },
      CAREER: { registryId: methodId("CAREER"), methodCode: "CAREER_ALIGNMENT_V01", methodVersion: 1, inferenceCategory: "HYBRID", permitsStrongAlignment: false },
      FINANCIAL: { registryId: methodId("FINANCIAL"), methodCode: "FINANCIAL_ALIGNMENT_V01", methodVersion: 1, inferenceCategory: "DETERMINISTIC", permitsStrongAlignment: false },
      GEOGRAPHIC_DELIVERY: { registryId: methodId("GEOGRAPHIC_DELIVERY"), methodCode: "GEOGRAPHIC_DELIVERY_ALIGNMENT_V01", methodVersion: 1, inferenceCategory: "HYBRID", permitsStrongAlignment: false },
      PERSONAL_PREFERENCE: { registryId: methodId("PERSONAL_PREFERENCE"), methodCode: "PERSONAL_PREFERENCE_ALIGNMENT_V01", methodVersion: 1, inferenceCategory: "HYBRID", permitsStrongAlignment: false },
      INTERNATIONAL_ACCESSIBILITY: { registryId: methodId("INTERNATIONAL_ACCESSIBILITY"), methodCode: "INTERNATIONAL_ACCESSIBILITY_V01", methodVersion: 1, inferenceCategory: "HYBRID", permitsStrongAlignment: false },
    },
    manifest,
    inputStates: states,
  };
}

export function supplyDimension(
  input: FitEvaluationInput,
  dimension: FitDimension,
  supplied: readonly DecisionManifestItem[],
): FitEvaluationInput {
  const config = dimensionConfig[dimension];
  const byPolicy = new Map<string, string[]>();
  for (const item of supplied) {
    const keys = byPolicy.get(item.ref.inputPolicyRegistryId) ?? [];
    keys.push(item.ref.manifestItemKey);
    byPolicy.set(item.ref.inputPolicyRegistryId, keys);
  }
  const states = input.inputStates.map((state) => {
    if (
      state.methodRegistryId !== config.methodId ||
      state.policyKey === config.completenessPolicy
    ) return state;
    const keys = byPolicy.get(state.inputPolicyRegistryId) ?? [];
    return {
      ...state,
      availability: keys.length > 0 ? "INCLUDED" as const : state.availability,
      manifestItemKeys: keys,
      completenessManifestItemKey: keys.length > 0 ? null : state.completenessManifestItemKey,
    };
  });
  return { ...input, manifest: [...input.manifest, ...supplied], inputStates: states };
}

export const policies = Object.fromEntries(
  FIT_DIMENSIONS.map((dimension) => [dimension, dimensionConfig[dimension]]),
) as typeof dimensionConfig;
