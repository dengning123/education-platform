export const FIT_DIMENSIONS = [
  "ACADEMIC",
  "CAREER",
  "FINANCIAL",
  "GEOGRAPHIC_DELIVERY",
  "PERSONAL_PREFERENCE",
  "INTERNATIONAL_ACCESSIBILITY",
] as const;

export type FitDimension = (typeof FIT_DIMENSIONS)[number];
export type FitAssessment =
  | "STRONG_ALIGNMENT"
  | "ALIGNMENT"
  | "MIXED"
  | "MISALIGNMENT"
  | "UNKNOWN";
export type FitConfidence = "HIGH" | "MEDIUM" | "LOW";
export type FitCoverage = "SUFFICIENT" | "PARTIAL" | "INSUFFICIENT";
export type FitDirection = "SUPPORTING" | "CONTRADICTING" | "LIMITING";
export type FitImportance =
  | "REQUIRED"
  | "STRONGLY_PREFERRED"
  | "PREFERRED"
  | "NEUTRAL"
  | "UNSPECIFIED";
export type InferenceCategory =
  | "DETERMINISTIC"
  | "REVIEWED_MAPPING"
  | "RULE"
  | "MODEL"
  | "HYBRID";
export type InputAvailability =
  | "INCLUDED"
  | "NOT_SUPPLIED"
  | "INCOMPLETE"
  | "UNKNOWN_SOURCE"
  | "STALE_SOURCE"
  | "SOURCE_CONFLICT"
  | "INAPPLICABLE";
export type FitSignalCode =
  | "MATERIAL_SUPPORT"
  | "MATERIAL_CONTRADICTION"
  | "NON_MATERIAL_SUPPORT"
  | "NON_MATERIAL_CONTRADICTION"
  | "LIMITING_CONTEXT"
  | "DIRECT_HIGH_IMPORTANCE_AUTHORITATIVE_MATCH";
export type FitReasonCode =
  | "STUDENT_PREFERENCE_UNSPECIFIED"
  | "REQUIRED_INPUT_UNAVAILABLE"
  | "MATERIAL_EVIDENCE_SUPPORTS_ALIGNMENT"
  | "MATERIAL_EVIDENCE_CONTRADICTS_INTENT"
  | "REQUIRED_CONSTRAINT_CONTRADICTED"
  | "MODEL_INFERENCE_LIMITATION"
  | "SOURCE_CONFLICT"
  | "FINANCIAL_INPUTS_INCOMPARABLE"
  | "INTERNATIONAL_EVIDENCE_INAPPLICABLE"
  | "STUDENT_INPUT_INCOMPLETE"
  | "PROGRAM_FACT_UNKNOWN"
  | "STALE_SOURCE"
  | "NO_AUTHORITATIVE_MAPPING"
  | "EVIDENCE_INSUFFICIENT"
  | "METHOD_UNSUPPORTED"
  | "INPUT_INAPPLICABLE"
  | "INTENT_CONFLICT";

export type FitMethodCode =
  | "ACADEMIC_ALIGNMENT_V01"
  | "CAREER_ALIGNMENT_V01"
  | "FINANCIAL_ALIGNMENT_V01"
  | "GEOGRAPHIC_DELIVERY_ALIGNMENT_V01"
  | "PERSONAL_PREFERENCE_ALIGNMENT_V01"
  | "INTERNATIONAL_ACCESSIBILITY_V01";

export type FitMethodByDimension = Readonly<{
  ACADEMIC: "ACADEMIC_ALIGNMENT_V01";
  CAREER: "CAREER_ALIGNMENT_V01";
  FINANCIAL: "FINANCIAL_ALIGNMENT_V01";
  GEOGRAPHIC_DELIVERY: "GEOGRAPHIC_DELIVERY_ALIGNMENT_V01";
  PERSONAL_PREFERENCE: "PERSONAL_PREFERENCE_ALIGNMENT_V01";
  INTERNATIONAL_ACCESSIBILITY: "INTERNATIONAL_ACCESSIBILITY_V01";
}>;

export type MappingRelation =
  | "FIELD_CLASSIFICATION"
  | "SUBFIELD_CLASSIFICATION"
  | "SUBJECT_CLASSIFICATION"
  | "COURSE_EQUIVALENCY"
  | "SKILL_ASSOCIATION"
  | "CAREER_ASSOCIATION"
  | "INDUSTRY_ASSOCIATION"
  | "STUDENT_COURSE_EQUIVALENCY"
  | "PROGRAM_RELATED_TO_CAREER"
  | "PROGRAM_ASSOCIATED_WITH_PATH"
  | "CLAIM_APPLIES_TO_CONCEPT";

export type FitInputPolicyKey =
  | "ACADEMIC_ALIGNMENT_V01/STUDENT_GOALS/ACADEMIC_INTENT"
  | "ACADEMIC_ALIGNMENT_V01/PROGRAM_COURSES/CURRICULUM"
  | "ACADEMIC_ALIGNMENT_V01/FIT_INTENTS/DECLARED_ACADEMIC_INTENT"
  | "ACADEMIC_ALIGNMENT_V01/STUDENT_COURSES/ALIGNMENT_COURSE_CONTEXT"
  | "ACADEMIC_ALIGNMENT_V01/STUDENT_COMPLETENESS/ACADEMIC_INPUT_AVAILABILITY"
  | "ACADEMIC_ALIGNMENT_V01/STUDENT_MAPPINGS/REVIEWED_STUDENT_COURSE_MAPPING"
  | "ACADEMIC_ALIGNMENT_V01/CATALOG_MAPPINGS/ACADEMIC_MAPPING"
  | "ACADEMIC_ALIGNMENT_V01/TAXONOMY_CONCEPTS/ACADEMIC_CONCEPT"
  | "CAREER_ALIGNMENT_V01/STUDENT_GOALS/CAREER_INTENT"
  | "CAREER_ALIGNMENT_V01/CATALOG_MAPPINGS/CAREER_MAPPING"
  | "CAREER_ALIGNMENT_V01/FIT_INTENTS/DECLARED_CAREER_INTENT"
  | "CAREER_ALIGNMENT_V01/PROGRAM_COURSES/CAREER_RELEVANT_CURRICULUM"
  | "CAREER_ALIGNMENT_V01/FIT_CONTEXT_CLAIMS/REVIEWED_CAREER_CONTEXT"
  | "CAREER_ALIGNMENT_V01/STUDENT_COMPLETENESS/CAREER_INPUT_AVAILABILITY"
  | "CAREER_ALIGNMENT_V01/TAXONOMY_CONCEPTS/CAREER_CONCEPT"
  | "FINANCIAL_ALIGNMENT_V01/STUDENT_PREFERENCES/BUDGET"
  | "FINANCIAL_ALIGNMENT_V01/PROGRAM_COSTS/COST_COMPONENTS"
  | "FINANCIAL_ALIGNMENT_V01/FIT_INTENTS/DECLARED_FINANCIAL_INTENT"
  | "FINANCIAL_ALIGNMENT_V01/STUDENT_COMPLETENESS/FINANCIAL_INPUT_AVAILABILITY"
  | "FINANCIAL_ALIGNMENT_V01/FINANCIAL_NORMALIZATIONS/COMPARABLE_FINANCIAL_ARTIFACT"
  | "GEOGRAPHIC_DELIVERY_ALIGNMENT_V01/STUDENT_PREFERENCES/GEOGRAPHIC_DELIVERY_INTENT"
  | "GEOGRAPHIC_DELIVERY_ALIGNMENT_V01/PROGRAM_VERSIONS/LOCATION_DELIVERY"
  | "GEOGRAPHIC_DELIVERY_ALIGNMENT_V01/FIT_INTENTS/DECLARED_GEOGRAPHIC_DELIVERY_INTENT"
  | "GEOGRAPHIC_DELIVERY_ALIGNMENT_V01/STUDENT_COMPLETENESS/GEOGRAPHIC_DELIVERY_INPUT_AVAILABILITY"
  | "PERSONAL_PREFERENCE_ALIGNMENT_V01/STUDENT_PREFERENCES/PROGRAM_CHARACTERISTICS"
  | "PERSONAL_PREFERENCE_ALIGNMENT_V01/PROGRAM_VERSIONS/OBSERVABLE_CHARACTERISTICS"
  | "PERSONAL_PREFERENCE_ALIGNMENT_V01/FIT_INTENTS/DECLARED_PERSONAL_PREFERENCE_INTENT"
  | "PERSONAL_PREFERENCE_ALIGNMENT_V01/STUDENT_COMPLETENESS/PERSONAL_PREFERENCE_INPUT_AVAILABILITY"
  | "INTERNATIONAL_ACCESSIBILITY_V01/STUDENT_GOALS/INTERNATIONAL_TARGET_PATH"
  | "INTERNATIONAL_ACCESSIBILITY_V01/FIT_CONTEXT_CLAIMS/INTERNATIONAL_ACCESS_EVIDENCE"
  | "INTERNATIONAL_ACCESSIBILITY_V01/FIT_INTENTS/DECLARED_INTERNATIONAL_PATH_INTENT"
  | "INTERNATIONAL_ACCESSIBILITY_V01/FIT_ACCESS_CONTEXT/AUTHORIZED_STUDENT_ACCESS_CONTEXT"
  | "INTERNATIONAL_ACCESSIBILITY_V01/STUDENT_COMPLETENESS/INTERNATIONAL_INPUT_AVAILABILITY"
  | "INTERNATIONAL_ACCESSIBILITY_V01/PROGRAM_VERSIONS/INTERNATIONAL_PROGRAM_FACTS"
  | "INTERNATIONAL_ACCESSIBILITY_V01/TAXONOMY_CONCEPTS/INTERNATIONAL_PATH_CONCEPT";

export type SourceClass =
  | "PROGRAM_CANONICAL_FACT"
  | "STUDENT_RAW_INTENT"
  | "STUDENT_RAW_ACADEMIC_HISTORY"
  | "STUDENT_RAW_ACCESS_CONTEXT"
  | "TAXONOMY_MAPPING"
  | "FIT_CONTEXT_REGULATORY"
  | "FIT_CONTEXT_CAREER"
  | "FIT_CONTEXT_FINANCIAL"
  | "FIT_CONTEXT_ACCESSIBILITY";

export type ManifestRef = Readonly<{
  manifestItemKey: string;
  sourceId: string;
  methodRegistryId: string;
  inputPolicyRegistryId: string;
  methodCode: FitMethodCode;
  policyKey: FitInputPolicyKey;
  sourceClass: SourceClass;
  authorityRole: "AUTHORITATIVE" | "LIMITING_CONTEXT";
}>;

export type IntentAuthority = Readonly<{
  importance: FitImportance;
  basis:
    | "STRUCTURED_STUDENT_DECLARATION"
    | "NORMALIZED_STUDENT_LANGUAGE"
    | "REVIEWED_INTERPRETATION";
  importanceEvidenceManifestKey: string | null;
  confirmedByStudent: boolean;
}>;

export type FinancialPeriod =
  | "MONTH"
  | "ACADEMIC_YEAR"
  | "CALENDAR_YEAR"
  | "PROGRAM_DURATION";
export type FinancialScope = "COMPONENT" | "PARTIAL_TOTAL" | "TOTAL_COST";
export type FinancialBasis = "GROSS" | "NET_OF_VERIFIED_FUNDING";
export type FinancialComparable = Readonly<{
  amount: string;
  currency: string;
  period: FinancialPeriod;
  scope: FinancialScope;
  basis: FinancialBasis;
  components: readonly string[];
}>;

export type FitIntent =
  | Readonly<{
      kind: "TAXONOMY_TARGET";
      intentId: string;
      dimension: "ACADEMIC" | "CAREER" | "INTERNATIONAL_ACCESSIBILITY";
      authority: IntentAuthority;
      conceptId: string;
      relation: "DESIRED" | "EXCLUDED";
    }>
  | Readonly<{
      kind: "LOCATION_CONSTRAINT";
      intentId: string;
      dimension: "GEOGRAPHIC_DELIVERY";
      authority: IntentAuthority;
      relation: "PREFERRED" | "ACCEPTABLE" | "REQUIRED" | "EXCLUDED";
      countryCode: string | null;
      regionCode: string | null;
      locality: string | null;
    }>
  | Readonly<{
      kind: "DELIVERY_CONSTRAINT";
      intentId: string;
      dimension: "GEOGRAPHIC_DELIVERY";
      authority: IntentAuthority;
      deliveryMode: "IN_PERSON" | "ONLINE" | "HYBRID";
      relation: "DESIRED" | "EXCLUDED";
    }>
  | Readonly<{
      kind: "FINANCIAL_CONSTRAINT";
      intentId: string;
      dimension: "FINANCIAL";
      authority: IntentAuthority;
      amount: string;
      semantics:
        | "HARD_TOTAL_COST_CEILING"
        | "PREFERRED_TOTAL_COST"
        | "HARD_TUITION_CEILING"
        | "PREFERRED_TUITION"
        | "AVAILABLE_FUNDING";
      currency: string;
      scope: FinancialScope;
      period: FinancialPeriod;
      basis: FinancialBasis;
      components: readonly string[];
    }>
  | Readonly<{
      kind: "DURATION_CONSTRAINT";
      intentId: string;
      dimension: "PERSONAL_PREFERENCE";
      authority: IntentAuthority;
      minimumMonths: string | null;
      maximumMonths: string | null;
    }>
  | Readonly<{
      kind: "PROGRAM_FEATURE_CONSTRAINT";
      intentId: string;
      dimension: "PERSONAL_PREFERENCE" | "INTERNATIONAL_ACCESSIBILITY";
      authority: IntentAuthority;
      feature:
        | "CAPSTONE_AVAILABLE"
        | "RESEARCH_OPPORTUNITY"
        | "FACULTY_ACCESS"
        | "COHORT_STRUCTURE"
        | "INTERNATIONAL_PATH_SUPPORT";
      expected: boolean;
    }>;

export type ProgramFact =
  | Readonly<{
      recordType: "PROGRAM_COURSE";
      field: "course_name" | "official_description";
      value: string;
    }>
  | Readonly<{
      recordType: "PROGRAM_COST";
      field:
        | "tuition_amount"
        | "mandatory_fees"
        | "estimated_living_cost"
        | "estimated_total_cost"
        | "currency"
        | "billing_basis";
      value: string;
    }>
  | Readonly<{
      recordType: "PROGRAM_VERSION";
      field: "delivery_mode";
      value: "IN_PERSON" | "ONLINE" | "HYBRID" | "UNKNOWN";
    }>
  | Readonly<{
      recordType: "PROGRAM_VERSION";
      field: "duration_months";
      value: string;
    }>
  | Readonly<{
      recordType: "PROGRAM_VERSION";
      field: "full_time" | "capstone_required";
      value: boolean;
    }>
  | Readonly<{
      recordType: "PROGRAM_VERSION";
      field: "stem_status";
      value: string;
    }>;

export type ContextClaimValue =
  | Readonly<{
      claimCode: "REGULATORY_WORK_AUTHORIZATION";
      allowed: boolean;
      authorizationType: string | null;
    }>
  | Readonly<{
      claimCode: "LICENSING_RESTRICTION";
      restricted: boolean;
      licenseType: string | null;
    }>
  | Readonly<{
      claimCode: "CITIZENSHIP_SECURITY_CLEARANCE_RESTRICTION";
      restricted: boolean;
      citizenships: readonly string[];
      clearanceType: string | null;
    }>
  | Readonly<{
      claimCode: "REVIEWED_CAREER_OUTCOME";
      outcome: string;
      populationDenominator: string;
      cohortPeriod: string;
      geography: string;
      reportingCoverage: string;
      outcomeDefinition: string;
      sampleSource: string;
      applicabilityScope: Readonly<{
        population: string;
        program: string;
        geography: string;
        period: string;
      }>;
    }>
  | Readonly<{
      claimCode: "JURISDICTION_PATH_ACCESSIBILITY";
      accessible: boolean;
      restrictionCode: string | null;
    }>;

export type DecisionManifestItem =
  | Readonly<{ kind: "FIT_INTENT"; ref: ManifestRef; intent: FitIntent }>
  | Readonly<{
      kind: "STUDENT_ACCESS_CONTEXT";
      ref: ManifestRef;
      citizenshipCountryCode: string | null;
      residenceCountryCode: string | null;
      jurisdictionCode: string | null;
      currentStatusCode: string | null;
      authorizationPathCode: string | null;
      targetPathCode: string | null;
    }>
  | Readonly<{
      kind: "PHASE2_GOAL";
      ref: ManifestRef;
      exposedFields: readonly ("GOAL_TYPE" | "CONCEPT_ID" | "GOAL_TEXT")[];
      goalType: string | null;
      conceptId: string | null;
      goalText: string | null;
    }>
  | Readonly<{
      kind: "PHASE2_PREFERENCE";
      ref: ManifestRef;
      exposedFields: readonly ("PREFERENCE_TYPE" | "VALUE")[];
      preferenceType: string | null;
      value: string | null;
    }>
  | Readonly<{
      kind: "PHASE2_COURSE";
      ref: ManifestRef;
      exposedFields: readonly (
        | "COURSE_CODE"
        | "COURSE_TITLE"
        | "COURSE_STATUS"
        | "TERM"
      )[];
      courseCode: string | null;
      courseTitle: string;
      courseStatus: string;
      term: string | null;
    }>
  | Readonly<{
      kind: "PHASE2_COMPLETENESS";
      ref: ManifestRef;
      educationContextId: string | null;
      domain: string;
      completeness: "COMPLETE" | "PARTIAL" | "UNKNOWN";
    }>
  | Readonly<{
      kind: "VERIFIED_MAPPING";
      ref: ManifestRef;
      mappingKind: "PHASE2_STUDENT" | "CATALOG" | "FIT_CONTEXT";
      relationRegistryId: string;
      relation: MappingRelation;
      conceptId: string;
      statusAtPin: "VERIFIED";
      reviewedAtAtPin: string;
      verificationEvidenceIdAtPin: string;
      retiredAtAtPin: null;
    }>
  | Readonly<{
      kind: "TAXONOMY_CONCEPT";
      ref: ManifestRef;
      conceptId: string;
      activeInPinnedRelease: true;
    }>
  | Readonly<{
      kind: "CANONICAL_PROGRAM_FACT";
      ref: ManifestRef;
      recordId: string;
      knowledgeStatus: "KNOWN";
      selectedObservationId: string;
      fact: ProgramFact;
    }>
  | Readonly<{
      kind: "HISTORICAL_CONTEXT_SELECTION";
      ref: ManifestRef;
      claimId: string;
      selectionId: string;
      observationId: string | null;
      knowledgeStatus:
        | "KNOWN"
        | "UNKNOWN"
        | "NOT_PUBLICLY_DISCLOSED"
        | "NOT_YET_RESEARCHED"
        | "NOT_YET_VERIFIED"
        | "NOT_APPLICABLE"
        | "SOURCE_CONFLICT"
        | "STALE";
      observationWorkflowStatusAtSelection: "VERIFIED" | null;
      observationReviewedAtAtSelection: string | null;
      authority:
        | "OFFICIAL_REGULATORY"
        | "OFFICIAL_INSTITUTIONAL"
        | "REVIEWED_STRUCTURED"
        | "APPLICABLE_OBSERVATIONAL"
        | "MODEL_GENERATED"
        | null;
      validFrom: string;
      validTo: string | null;
      programVersionId: string | null;
      geographyCode: string | null;
      jurisdictionCode: string | null;
      pathCode: string | null;
      value: ContextClaimValue | null;
    }>
  | Readonly<{
      kind: "DIRECT_FINANCIAL_COMPARABLE";
      ref: ManifestRef;
      sourcePinId: string;
      financialContractVersion: "FINANCIAL_BILLING_BASIS_V014";
      financialConstraintIntentId: string;
      comparable: FinancialComparable;
    }>
  | Readonly<{
      kind: "APPROVED_FINANCIAL_NORMALIZATION";
      ref: ManifestRef;
      normalizationId: string;
      fieldObservationId: string;
      financialConstraintIntentId: string;
      intentSetId: string;
      financialContractVersion: "FINANCIAL_BILLING_BASIS_V014";
      methodCode: string;
      methodVersion: number;
      verificationEvidenceId: string;
      source: FinancialComparable;
      target: FinancialComparable;
      conversionEvidenceId: string;
    }>;

export type RegistryIdentity = Readonly<{
  id: string;
  code: string;
  version: string | null;
}>;
export type FrozenReviewState = Readonly<{
  status: "VERIFIED";
  reviewedBy: string;
  reviewedAt: string;
  retiredAt: null;
  retirementReason: null;
}>;
export type FrozenVerifiedArtifactState = FrozenReviewState &
  Readonly<{ verificationEvidenceId: string }>;

export type ResolvedMethodContract = Readonly<{
  identity: RegistryIdentity;
  dimension: FitDimension;
  inferenceCategory: InferenceCategory;
  permitsStrongAlignment: boolean;
  materialityContractCanonicalJson: string;
  definitionState: FrozenVerifiedArtifactState;
  sourceClassPolicies: readonly Readonly<{
    methodRegistryId: string;
    sourceClassRegistryId: string;
    sourceClassCode: string;
    disposition: "ALLOWED" | "FORBIDDEN";
  }>[];
  inputPolicies: readonly Readonly<{
    identity: RegistryIdentity;
    methodRegistryId: string;
    policyKey: FitInputPolicyKey;
    inputDomain: string;
    fieldName: string;
    disposition: "ALLOWED" | "FORBIDDEN";
    requirement: "REQUIRED" | "OPTIONAL";
    acceptableAuthority: string | null;
    acceptableClaimStatus: string | null;
    programFields: readonly Readonly<{
      methodRegistryId: string;
      inputPolicyRegistryId: string;
      recordType: string;
      fieldName: string;
    }>[];
    permitsDeterministicUse: boolean;
    permitsModelUse: boolean;
  }>[];
  mappingRelations: readonly Readonly<{
    methodRegistryId: string;
    relationRegistryId: string;
    relationCode: string;
    allowedAssessments: readonly FitAssessment[];
    permitsStrongAlignment: boolean;
  }>[];
  signalTypes: readonly Readonly<{
    identity: RegistryIdentity;
    methodRegistryId: string;
    direction: FitDirection;
    material: boolean;
    allowedInferenceCategories: readonly InferenceCategory[];
    permitsStrongAlignment: boolean;
    description: string;
  }>[];
}>;

export type ResolvedFitContract = Readonly<{
  release: RegistryIdentity &
    Readonly<{
      code: "fit-v0.1";
      version: "v0.1";
      specificationDigest: string;
      upstreamContractVersion: "phase2-eligibility-v0.1";
      definitionState: FrozenReviewState;
    }>;
  evaluatorBuild: RegistryIdentity &
    Readonly<{
      evaluatorName: string;
      evaluatorVersion: string;
      buildHash: string;
      definitionState: FrozenVerifiedArtifactState;
    }>;
  semanticSourceClasses: readonly Readonly<{
    sourceClassRegistryId: string;
    sourceClassCode: string;
    ownerLayer: "PHASE1" | "PHASE2" | "PHASE3" | "PROHIBITED";
    fitPermitted: boolean;
    description: string;
  }>[];
  mappingRelationDefinitions: readonly Readonly<{
    relationRegistryId: string;
    relationCode: string;
    relationDomain: "CATALOG" | "STUDENT" | "FIT_CONTEXT";
    description: string;
  }>[];
  methods: Readonly<Record<FitDimension, ResolvedMethodContract>>;
  reasons: readonly Readonly<{
    identity: RegistryIdentity;
    contractReleaseRegistryId: string;
    dimension: FitDimension | null;
    reasonFamily: string;
    direction: FitDirection;
    allowedAssessments: readonly FitAssessment[];
    description: string;
    definitionState: FrozenReviewState;
  }>[];
  financialNormalizations: readonly Readonly<{
    identity: RegistryIdentity;
    contractReleaseRegistryId: string;
    sourceScope: FinancialScope;
    targetScope: FinancialScope;
    sourcePeriod: FinancialPeriod;
    targetPeriod: FinancialPeriod;
    sourceBasis: FinancialBasis;
    targetBasis: FinancialBasis;
    sourceCurrency: string | null;
    targetCurrency: string | null;
    normalizationContractCanonicalJson: string;
    definitionState: FrozenVerifiedArtifactState;
  }>[];
}>;

export type DimensionMethodInput<
  M extends FitMethodCode,
  C extends InferenceCategory,
  S extends boolean,
> = Readonly<{
  registryId: string;
  methodCode: M;
  methodVersion: 1;
  inferenceCategory: C;
  permitsStrongAlignment: S;
}>;

export type FitInputState = Readonly<{
  methodRegistryId: string;
  inputPolicyRegistryId: string;
  methodCode: FitMethodCode;
  policyKey: FitInputPolicyKey;
  requirement: "REQUIRED" | "OPTIONAL";
  availability: InputAvailability;
  manifestItemKeys: readonly string[];
  completenessManifestItemKey: string | null;
  provenanceManifestItemKey: string | null;
}>;

export type FitEvaluationInput = Readonly<{
  schemaVersion: "fit-v0.1";
  contractRelease: Readonly<{
    registryId: string;
    releaseCode: "fit-v0.1";
    specificationVersion: "v0.1";
    digest: string;
  }>;
  resolvedContract: ResolvedFitContract;
  evaluator: Readonly<{
    registryId: string;
    name: string;
    version: string;
    buildHash: string;
  }>;
  evaluationAsOf: string;
  profile: Readonly<{ versionId: string; snapshotHash: string }>;
  intentSet: Readonly<{ id: string; snapshotHash: string }>;
  programVersionId: string;
  taxonomyReleaseCode: string;
  methods: Readonly<{
    ACADEMIC: DimensionMethodInput<"ACADEMIC_ALIGNMENT_V01", "HYBRID", true>;
    CAREER: DimensionMethodInput<"CAREER_ALIGNMENT_V01", "HYBRID", false>;
    FINANCIAL: DimensionMethodInput<
      "FINANCIAL_ALIGNMENT_V01",
      "DETERMINISTIC",
      false
    >;
    GEOGRAPHIC_DELIVERY: DimensionMethodInput<
      "GEOGRAPHIC_DELIVERY_ALIGNMENT_V01",
      "HYBRID",
      false
    >;
    PERSONAL_PREFERENCE: DimensionMethodInput<
      "PERSONAL_PREFERENCE_ALIGNMENT_V01",
      "HYBRID",
      false
    >;
    INTERNATIONAL_ACCESSIBILITY: DimensionMethodInput<
      "INTERNATIONAL_ACCESSIBILITY_V01",
      "HYBRID",
      false
    >;
  }>;
  manifest: readonly DecisionManifestItem[];
  inputStates: readonly FitInputState[];
}>;

export type FitSignal = Readonly<{
  methodRegistryId: string;
  signalTypeRegistryId: string;
  inputPolicyRegistryIds: readonly string[];
  mappingRelationRegistryId: string | null;
  signalCode: FitSignalCode;
  direction: FitDirection;
  material: boolean;
  inferenceCategory: InferenceCategory;
  evidenceManifestRefs: readonly string[];
  intentManifestRef: string | null;
  requiredConstraintContradiction: boolean;
  internationalHighImpact: boolean;
  model: Readonly<{ version: string; buildHash: string }> | null;
}>;

export type FitReason = Readonly<{
  methodRegistryId: string;
  reasonDefinitionRegistryId: string;
  reasonCode: FitReasonCode;
  direction: FitDirection;
  signalCode: FitSignalCode | null;
  signalTypeRegistryId: string | null;
  inputPolicyKey: FitInputPolicyKey | null;
  inputPolicyRegistryId: string | null;
  mappingRelationRegistryId: string | null;
  exactManifestRefs: readonly string[];
}>;

export type LimitingInput = Readonly<{
  methodRegistryId: string;
  reasonCode: FitReasonCode;
  reasonDefinitionRegistryId: string;
  inputPolicyKey: FitInputPolicyKey;
  inputPolicyRegistryId: string;
  availability: Exclude<InputAvailability, "INCLUDED">;
  completenessManifestRef: string | null;
  provenanceManifestRef: string | null;
}>;

export type DimensionDecision<D extends FitDimension> = Readonly<{
  dimension: D;
  methodRegistryId: string;
  methodCode: FitMethodByDimension[D];
  methodVersion: 1;
  assessment: FitAssessment;
  confidence: FitConfidence;
  evidenceCoverage: FitCoverage;
  inferenceCategory: InferenceCategory;
  signals: readonly FitSignal[];
  reasons: readonly FitReason[];
  limitingInputs: readonly LimitingInput[];
  exactManifestRefs: readonly string[];
}>;

export type FitEvaluationOutput = Readonly<{
  schemaVersion: "fit-v0.1";
  dimensions: Readonly<{
    ACADEMIC: DimensionDecision<"ACADEMIC">;
    CAREER: DimensionDecision<"CAREER">;
    FINANCIAL: DimensionDecision<"FINANCIAL">;
    GEOGRAPHIC_DELIVERY: DimensionDecision<"GEOGRAPHIC_DELIVERY">;
    PERSONAL_PREFERENCE: DimensionDecision<"PERSONAL_PREFERENCE">;
    INTERNATIONAL_ACCESSIBILITY: DimensionDecision<"INTERNATIONAL_ACCESSIBILITY">;
  }>;
}>;

export type DimensionEvidenceInterpretation<D extends FitDimension> = Readonly<{
  dimension: D;
  methodRegistryId: string;
  validatedAgainstResolvedContract: true;
  signals: readonly FitSignal[];
  reasons: readonly FitReason[];
  limitingInputs: readonly LimitingInput[];
  hasMaterialSupport: boolean;
  hasMaterialContradiction: boolean;
  hasRequiredConstraintContradiction: boolean;
  hasQualifiedStrongAlignment: boolean;
  hasDirectionalBasis: boolean;
  confidence: FitConfidence;
  evidenceCoverage: FitCoverage;
}>;

export type FitEngineInput = FitEvaluationInput;
export type FitEngineOutput = FitEvaluationOutput;
