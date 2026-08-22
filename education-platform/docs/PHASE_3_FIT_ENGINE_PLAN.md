# Phase 3 Fit Engine v0.1 — Design and Implementation Plan

Status: **IMPLEMENTATION COMPLETE — PROMOTED TO FINAL PHASE 3 FREEZE**  
Phase: **Phase 3 — Fit**  
Target contract: **Fit v0.1**  
Product semantic baseline: [`PHASE_3_FIT_SPEC.md`](PHASE_3_FIT_SPEC.md)  
Sole engine semantic authority: the exact verified database registry frozen by
migrations `009`–`011`  
Authoritative persistence and final integrity boundary: frozen migrations
`009`–`018`

This document governed the authorized implementation of a pure, deterministic,
strongly typed Fit evaluator package. It does not authorize an API, service,
new database migration, evaluator-build registration, score, ranking,
probability, recommendation, or deployment.

Implementation and the separately authorized production work are complete.
The authoritative released state and post-freeze policy are recorded in
[`PHASE_3_FREEZE.md`](PHASE_3_FREEZE.md).

> **Resolved implementation gate:** frozen Migration `014` preserves and
> validates independent `billing_basis` authority, exact period/scope/basis/
> component comparability, typed normalization inputs/factors, funding
> isolation, and v014 fingerprints. Frozen Migration `015` moves complete live
> validation to seal and provides deterministic semantic-pin replay. The prior
> Migration 011 Financial blocker is closed without editing migrations
> `009`–`011`.

The engine must implement the semantic specification exactly and produce
outputs that the frozen SQL finalizer can validate. Where implementation detail
is not fixed by the specification or migrations, the engine must fail closed
with `UNKNOWN` and a structured limiting reason rather than invent semantics.

## 1. Goals and non-goals

The implementation goal is a persistence-neutral function:

```text
exact typed Fit inputs
  → six independent dimension evaluators
  → six categorical results with signals, reasons, confidence, and coverage
```

The engine must be:

- pure: no database, network, clock, random, environment, filesystem, or model
  calls inside evaluation;
- deterministic: equivalent canonical inputs produce deep-equal outputs;
- exhaustive: exactly one output for every canonical dimension;
- evidence-bounded: every material signal links to exact supplied evidence;
- persistence-neutral: no SQL row type, Supabase client, UUID generator, or
  repository import in the core package;
- fail-closed: unsupported, stale, conflicting, inapplicable, or insufficient
  evidence becomes an explicit limiting result;
- separate from Eligibility, Competitiveness, Admission Probability,
  Recommendation, and ranking.

## 2. Planned package structure

The authorized implementation adds one package:

```text
packages/fit-engine/
  package.json
  tsconfig.json
  src/
    contracts.ts
    evaluate-fit.ts
    canonicalize.ts
    coverage.ts
    confidence.ts
    combine-signals.ts
    reasons.ts
    dimensions/
      academic.ts
      career.ts
      financial.ts
      geographic-delivery.ts
      personal-preference.ts
      international-accessibility.ts
  test/
    contract.test.ts
    dimensions/
    adversarial/
    replay/
```

Responsibilities:

- `contracts.ts`: closed unions and readonly persistence-neutral DTOs;
- `evaluate-fit.ts`: exhaustive dispatch and six-result assembly only;
- `canonicalize.ts`: stable ordering and duplicate rejection for replay;
- `coverage.ts`: shared fact detection for declared evidence states; each
  dimension method owns the coverage conclusion;
- `confidence.ts`: shared fact detection only (for example, whether all
  directional signals are model-derived); each dimension method owns the
  confidence conclusion;
- `combine-signals.ts`: sharply restricted universal categorical precedence
  over already method-valid signals, with no semantic classification;
- `reasons.ts`: stable reason construction and reason/result compatibility;
- `dimensions/*`: only dimension-owned policy and signal derivation;
- `test/*`: semantic, adversarial, property-style, and cross-layer fixtures.

No database adapter belongs in this package. A later application adapter may
translate frozen database records into these DTOs and persist the output, but
the adapter must not contain decision semantics. The frozen database registry
is the engine's sole machine-readable semantic authority for the pinned
release: package constants, handwritten switch tables, fixtures, and adapter
defaults may not restate or override registry meaning.

### 2.1 Implementation checkpoint — 2026-08-21

At this checkpoint, the authorized pure package existed at
`packages/fit-engine`. It included closed persistence-neutral DTOs, exact resolved-registry
identity and lifecycle validation, manifest/policy/source/field ownership
checks, deterministic canonicalization, exact decimal comparison, the
boolean-only precedence combiner, six independent dimension evaluators,
structured reasons/limiting inputs, and runtime exclusion of Eligibility,
Competitiveness, scores, weights, rankings, probabilities, and
recommendations. Its initial contract, dimension, replay, Financial funding,
and adversarial suite is **14/14 PASS**.

At that date, this checkpoint was not an implementation freeze or production release. A
database resolver/persistence adapter, database-generated exact registry
fixture, accepted/rejected cross-layer SQL corpus, evaluator-build
registration, API, operational review, and final Phase 3 freeze remained
future gates. All were subsequently closed by
[`PHASE_3_FREEZE.md`](PHASE_3_FREEZE.md).

## 3. Strongly typed persistence-neutral contracts

The following TypeScript-like declarations are design notation, not production
code. Final names may change only if their semantics remain identical.

### 3.1 Closed semantic unions

```ts
type FitDimension =
  | "ACADEMIC"
  | "CAREER"
  | "FINANCIAL"
  | "GEOGRAPHIC_DELIVERY"
  | "PERSONAL_PREFERENCE"
  | "INTERNATIONAL_ACCESSIBILITY";

type FitAssessment =
  | "STRONG_ALIGNMENT"
  | "ALIGNMENT"
  | "MIXED"
  | "MISALIGNMENT"
  | "UNKNOWN";

type FitConfidence = "HIGH" | "MEDIUM" | "LOW";
type FitCoverage = "SUFFICIENT" | "PARTIAL" | "INSUFFICIENT";
type FitDirection = "SUPPORTING" | "CONTRADICTING" | "LIMITING";
type FitImportance =
  | "REQUIRED"
  | "STRONGLY_PREFERRED"
  | "PREFERRED"
  | "NEUTRAL"
  | "UNSPECIFIED";
type InferenceCategory =
  | "DETERMINISTIC"
  | "REVIEWED_MAPPING"
  | "RULE"
  | "MODEL"
  | "HYBRID";
type InputAvailability =
  | "INCLUDED"
  | "NOT_SUPPLIED"
  | "INCOMPLETE"
  | "UNKNOWN_SOURCE"
  | "STALE_SOURCE"
  | "SOURCE_CONFLICT"
  | "INAPPLICABLE";

type FitSignalCode =
  | "MATERIAL_SUPPORT"
  | "MATERIAL_CONTRADICTION"
  | "NON_MATERIAL_SUPPORT"
  | "NON_MATERIAL_CONTRADICTION"
  | "LIMITING_CONTEXT"
  | "DIRECT_HIGH_IMPORTANCE_AUTHORITATIVE_MATCH";

type FitReasonCode =
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
```

No numeric score, weight, percentage, rank, percentile, likelihood, or
probability type is permitted in the decision contract.

### 3.2 Exact manifest references and field exposure

The core input is not a bag of evidence. Every supplied value is one member of
a closed v0.1 decision-manifest union and exposes only the exact fields the
pinned method may read. There is no `Record<string, unknown>`, generic
structured value, generic external metric, or generic derived feature.

```ts
type ManifestRef = Readonly<{
  manifestItemKey: string;
  sourceId: string;
  methodRegistryId: string;
  inputPolicyRegistryId: string;
  methodCode: FitMethodCode;
  policyKey: FitInputPolicyKey;
  sourceClass:
    | "PROGRAM_CANONICAL_FACT"
    | "STUDENT_RAW_INTENT"
    | "STUDENT_RAW_ACADEMIC_HISTORY"
    | "STUDENT_RAW_ACCESS_CONTEXT"
    | "TAXONOMY_MAPPING"
    | "FIT_CONTEXT_REGULATORY"
    | "FIT_CONTEXT_CAREER"
    | "FIT_CONTEXT_FINANCIAL"
    | "FIT_CONTEXT_ACCESSIBILITY";
  authorityRole: "AUTHORITATIVE" | "LIMITING_CONTEXT";
}>;

type FitMethodCode =
  | "ACADEMIC_ALIGNMENT_V01"
  | "CAREER_ALIGNMENT_V01"
  | "FINANCIAL_ALIGNMENT_V01"
  | "GEOGRAPHIC_DELIVERY_ALIGNMENT_V01"
  | "PERSONAL_PREFERENCE_ALIGNMENT_V01"
  | "INTERNATIONAL_ACCESSIBILITY_V01";

type MappingRelation =
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

type FitInputPolicyKey =
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
```

`FitInputPolicyKey` enumerates the frozen allowed policy identities. Forbidden
policies are intentionally unrepresentable. The adapter rejects any manifest
item whose method, policy, source class, authority role, or exposed field is
not an exact registered combination.

### 3.3 Closed typed intent union

```ts
type IntentAuthority = Readonly<{
  importance: FitImportance;
  basis:
    | "STRUCTURED_STUDENT_DECLARATION"
    | "NORMALIZED_STUDENT_LANGUAGE"
    | "REVIEWED_INTERPRETATION";
  importanceEvidenceManifestKey: string | null;
  confirmedByStudent: boolean;
}>;

type FitIntent =
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
      scope: "COMPONENT" | "PARTIAL_TOTAL" | "TOTAL_COST";
      period: "MONTH" | "ACADEMIC_YEAR" | "CALENDAR_YEAR" | "PROGRAM_DURATION";
      basis: "GROSS" | "NET_OF_VERIFIED_FUNDING";
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
```

The adapter supplies the frozen intent snapshot hash and a manifest item for
each intent. `REQUIRED` authority and intent conflicts must already satisfy
migration `010`; the core independently fails closed if the typed contract is
inconsistent.

DTO validation also enforces semantic ownership, not merely the `dimension`
tag. `PERSONAL_PREFERENCE` accepts only duration and allowlisted observable
program-characteristic semantics. It rejects financial amounts/funding,
location/delivery, career targets/outcomes, international-path/access, and
Eligibility semantics even if a caller wraps or labels them as a personal
preference. In particular, `INTERNATIONAL_PATH_SUPPORT` is valid only with
`dimension: "INTERNATIONAL_ACCESSIBILITY"`; the cross-product otherwise
suggested by the union is rejected before evaluation.

### 3.4 Closed decision-manifest item union

```ts
type ProgramFact =
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
        | "estimated_total_cost";
      value: string;
    }>
  | Readonly<{
      recordType: "PROGRAM_COST";
      field: "currency" | "billing_basis";
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

type ContextClaimValue =
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

type DecisionManifestItem =
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
        "COURSE_CODE" | "COURSE_TITLE" | "COURSE_STATUS" | "TERM"
      )[];
      courseCode: string | null;
      courseTitle: string;
      courseStatus: string;
      term: string | null;
    }>
  | Readonly<{
      kind: "PHASE2_COMPLETENESS";
      ref: ManifestRef;
      exposedFields: readonly (
        "EDUCATION_CONTEXT_ID" | "DOMAIN" | "COMPLETENESS"
      )[];
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
      comparable: Readonly<FinancialComparable>;
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
      source: Readonly<FinancialComparable>;
      target: Readonly<FinancialComparable>;
      conversionEvidenceId: string;
    }>;

type FinancialComparable = Readonly<{
  amount: string;
  currency: string;
  period: "MONTH" | "ACADEMIC_YEAR" | "CALENDAR_YEAR" | "PROGRAM_DURATION";
  scope: "COMPONENT" | "PARTIAL_TOTAL" | "TOTAL_COST";
  basis: "GROSS" | "NET_OF_VERIFIED_FUNDING";
  components: readonly string[];
}>;
```

This union models exact field exposure, typed canonical facts, verified mapping
relation semantics, pinned historical context selection/observation state,
typed financial values, v014 direct source-pin comparables, and approved
normalization artifacts without copying database row types. A source reused by
two dimensions appears as two manifest items with distinct method/policy
identity and the same immutable source ID.

### 3.5 Persistence-neutral resolved registry contract

The application boundary mechanically resolves the exact active verified
registry graph into a persistence-neutral `ResolvedFitContract`. It is an
immutable semantic input, not an application-authored configuration:

```ts
type RegistryIdentity = Readonly<{
  id: string;
  code: string;
  version: string | null;
}>;

type FrozenReviewState = Readonly<{
  status: "VERIFIED";
  reviewedBy: string;
  reviewedAt: string;
  retiredAt: null;
  retirementReason: null;
}>;

type FrozenVerifiedArtifactState = FrozenReviewState & Readonly<{
  verificationEvidenceId: string;
}>;

type ResolvedFitContract = Readonly<{
  release: RegistryIdentity & Readonly<{
    code: "fit-v0.1";
    version: "v0.1";
    specificationDigest: string;
    upstreamContractVersion: "phase2-eligibility-v0.1";
    definitionState: FrozenReviewState;
  }>;
  evaluatorBuild: RegistryIdentity & Readonly<{
    evaluatorName: string;
    evaluatorVersion: string;
    buildHash: string;
    definitionState: FrozenVerifiedArtifactState;
  }>;
  semanticSourceClasses: readonly Readonly<{
    sourceClassRegistryId: string; // exact DB identity: source_class_code
    sourceClassCode: string;
    ownerLayer: "PHASE1" | "PHASE2" | "PHASE3" | "PROHIBITED";
    fitPermitted: boolean;
    description: string;
  }>[];
  mappingRelationDefinitions: readonly Readonly<{
    relationRegistryId: string; // exact DB identity: relation_code
    relationCode: string;
    relationDomain: "CATALOG" | "STUDENT" | "FIT_CONTEXT";
    description: string;
  }>[];
  methods: Readonly<Record<FitDimension, Readonly<{
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
  }>>>;
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
    sourceScope: "COMPONENT" | "PARTIAL_TOTAL" | "TOTAL_COST";
    targetScope: "COMPONENT" | "PARTIAL_TOTAL" | "TOTAL_COST";
    sourcePeriod:
      | "MONTH" | "ACADEMIC_YEAR" | "CALENDAR_YEAR" | "PROGRAM_DURATION";
    targetPeriod:
      | "MONTH" | "ACADEMIC_YEAR" | "CALENDAR_YEAR" | "PROGRAM_DURATION";
    sourceBasis: "GROSS" | "NET_OF_VERIFIED_FUNDING";
    targetBasis: "GROSS" | "NET_OF_VERIFIED_FUNDING";
    sourceCurrency: string | null;
    targetCurrency: string | null;
    normalizationContractCanonicalJson: string;
    definitionState: FrozenVerifiedArtifactState;
  }>[];
}>;
```

`ResolvedFitContract` is a complete frozen projection, not a convenient subset.
`RegistryIdentity` fields are opaque identifiers and semantic labels, not SQL
row types. The resolver must preserve the exact release ID/digest and lifecycle
guardrails; evaluator-build authorization; every semantic source-class
definition and per-method disposition; method IDs, versions, inference
categories, materiality contracts, verification evidence, and strong-alignment
permissions; every input-policy ID/domain/field/requirement/authority/status/
deterministic/model rule and exact program-field tuple; every mapping-relation
definition and per-method relation policy; every signal-type ID, reason-
definition ID, normalization ID, allowed assessment, direction, materiality,
description, and semantic payload. Exact registry IDs are carried even where
the database identity is a natural key (`source_class_code` or
`relation_code`). It must canonicalize representation only; it may not omit
guardrails, infer defaults, repair omissions, reinterpret JSON, or select a
"close enough" definition.

The engine accepts only the one exact registry identity graph for which its
build was verified. Any missing, extra, retired, unverified, duplicate,
wrong-release, wrong-method, wrong-version, wrong-digest, or semantically
different registry member is contract drift and fails closed before dimension
evaluation. Drift never falls back to compiled constants and never yields a
partially evaluated result.

### 3.6 Exact input DTO

```ts
type FitEvaluationInput = Readonly<{
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
    ACADEMIC:
      DimensionMethodInput<"ACADEMIC_ALIGNMENT_V01", "HYBRID", true>;
    CAREER:
      DimensionMethodInput<"CAREER_ALIGNMENT_V01", "HYBRID", false>;
    FINANCIAL:
      DimensionMethodInput<"FINANCIAL_ALIGNMENT_V01", "DETERMINISTIC", false>;
    GEOGRAPHIC_DELIVERY:
      DimensionMethodInput<
        "GEOGRAPHIC_DELIVERY_ALIGNMENT_V01", "HYBRID", false
      >;
    PERSONAL_PREFERENCE:
      DimensionMethodInput<
        "PERSONAL_PREFERENCE_ALIGNMENT_V01", "HYBRID", false
      >;
    INTERNATIONAL_ACCESSIBILITY:
      DimensionMethodInput<
        "INTERNATIONAL_ACCESSIBILITY_V01", "HYBRID", false
      >;
  }>;
  manifest: readonly DecisionManifestItem[];
  inputStates: readonly FitInputState[];
}>;

type DimensionMethodInput<
  M extends FitMethodCode,
  C extends InferenceCategory,
  S extends boolean
> = Readonly<{
  registryId: string;
  methodCode: M;
  methodVersion: 1;
  inferenceCategory: C;
  permitsStrongAlignment: S;
}>;

type FitInputState = Readonly<{
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
```

The implementation may export `FitEngineInput` as a deprecated-free alias of
`FitEvaluationInput`, but `FitEvaluationInput` is the conceptual public name.
The manifest is exact: every `INCLUDED` state has matching typed manifest
members; every other state has no supplied value and carries the required
completeness/provenance reference. Extra, unreferenced, wrong-method, or
wrong-policy items are invalid.

`FitEvaluationInput` contains no Eligibility status, gap, rule result,
competitiveness, prestige/ranking, recommendation, generic student-capability
score, or admission probability. Adjacent Eligibility may exist only in an
outer orchestration envelope and is excluded from core input, output, signals,
reasons, and Fit fingerprints.

### 3.7 Exact six-result output DTO

```ts
type FitEvaluationOutput = Readonly<{
  schemaVersion: "fit-v0.1";
  dimensions: Readonly<{
    ACADEMIC: DimensionDecision<"ACADEMIC">;
    CAREER: DimensionDecision<"CAREER">;
    FINANCIAL: DimensionDecision<"FINANCIAL">;
    GEOGRAPHIC_DELIVERY: DimensionDecision<"GEOGRAPHIC_DELIVERY">;
    PERSONAL_PREFERENCE: DimensionDecision<"PERSONAL_PREFERENCE">;
    INTERNATIONAL_ACCESSIBILITY:
      DimensionDecision<"INTERNATIONAL_ACCESSIBILITY">;
  }>;
}>;

type FitMethodByDimension = Readonly<{
  ACADEMIC: "ACADEMIC_ALIGNMENT_V01";
  CAREER: "CAREER_ALIGNMENT_V01";
  FINANCIAL: "FINANCIAL_ALIGNMENT_V01";
  GEOGRAPHIC_DELIVERY: "GEOGRAPHIC_DELIVERY_ALIGNMENT_V01";
  PERSONAL_PREFERENCE: "PERSONAL_PREFERENCE_ALIGNMENT_V01";
  INTERNATIONAL_ACCESSIBILITY: "INTERNATIONAL_ACCESSIBILITY_V01";
}>;

type DimensionDecision<D extends FitDimension> = Readonly<{
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

type FitSignal = Readonly<{
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

type FitReason = Readonly<{
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

type LimitingInput = Readonly<{
  methodRegistryId: string;
  reasonCode: FitReasonCode;
  reasonDefinitionRegistryId: string;
  inputPolicyKey: FitInputPolicyKey;
  inputPolicyRegistryId: string;
  availability: Exclude<InputAvailability, "INCLUDED">;
  completenessManifestRef: string | null;
  provenanceManifestRef: string | null;
}>;
```

The implementation may export `FitEngineOutput` only as an alias of
`FitEvaluationOutput`; `FitEvaluationOutput` is the conceptual public name.
The explicit object shape guarantees exactly six outputs and gives every
result structured limiting information plus exact manifest references.
Input and output preserve, without aliasing or regeneration, every exact
method, policy, signal, reason, and relation registry identity used to validate
or explain a decision. Relation IDs are retained when a relation authorized an
interpretation; absence of a relation is `null`, never an invented generic ID.

Core v0.1 emits no prose field on the dimension, signal, reason, or limiting
DTO and does not generate presentation prose. Human-readable explanation
belongs to a separate outer presentation layer, derived from structured
reasons under its own contract. Presentation prose is excluded from core
output and all decision/result fingerprints. There is no Eligibility field and
no aggregate decision DTO.

### 3.8 Dimension evidence interpretation boundary

Each dimension first converts validated typed evidence into a method-owned
intermediate value. This keeps evidence semantics out of the universal
combiner while making all decisions auditable:

```ts
type DimensionEvidenceInterpretation<D extends FitDimension> = Readonly<{
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
```

The required flow is:

```text
typed manifest + exact resolved registry contract
  → dimension-owned validation and semantic interpretation
  → DimensionEvidenceInterpretation
  → boolean-only universal precedence
  → DimensionDecision with the same exact registry IDs
```

The booleans are derived and cross-checked by the owning method from its
registered signal identities. They are not adapter assertions and cannot be
accepted without the signals/reasons that prove them. As an optional
implementation optimization, this intermediate may be internal and
allocation-free, provided tests prove byte-equivalent output and preserve the
same validation boundary.

## 4. Exact six dimension contracts

All six evaluators consume only their pinned method input. Evidence cannot
cross dimensions merely because it appears useful. Each contract below uses
the same required A–M checklist.

### 4.0 Strict absence semantics for every dimension

Absence is a directional fact and is never inferred from silence. Across all
six dimensions:

- no manifest item, no mapping, no observation, no outcome row, no mention in
  text, or a non-`INCLUDED` input state means unavailable evidence, not absence;
- `NOT_SUPPLIED`, `INCOMPLETE`, `UNKNOWN_SOURCE`, `STALE_SOURCE`,
  `SOURCE_CONFLICT`, and `INAPPLICABLE` are distinct limiting states and never
  become a contradicting signal;
- a method may emit an absence-based contradiction only when its pinned
  materiality contract declares that exact observable domain closed and the
  supplied authoritative evidence marks that same domain `COMPLETE` for the
  exact program version, target, applicability scope, and validity period;
- a direct authoritative negative fact may contradict without an absence
  inference, but catalog silence, missing rows, generic completeness, adapter
  knowledge, or a complete open domain never may;
- the dimension method, not a shared utility or adapter, decides whether the
  scope is closed, complete, comparable, and material;
- if omitted evidence could contain the feature, direction, mapping, funding,
  restriction, or characteristic, coverage is `INSUFFICIENT` and assessment is
  `UNKNOWN`.

This is especially strict for Academic and Career. A course catalog that does
not mention a subject does not prove the subject is absent; no reviewed career
mapping does not prove career misalignment; sparse or non-applicable outcomes
do not prove a career path is unavailable. Academic absence requires complete
authoritative curriculum/structure coverage for the exact program version and
target. Career absence requires an authoritative explicit negative program
fact or complete reviewed program-level coverage for the exact feature and
applicability scope. Otherwise both dimensions return `UNKNOWN` with a
limiting reason.

The frozen v0.1 materiality JSON does not currently declare a structured closed
observable `COMPLETE` domain. Therefore no v0.1 method may manufacture an
absence contradiction from completeness or silence alone; an additive,
reviewed registry version is required before that path can be implemented.

### 4.1 Academic Alignment

- **A. Permitted categories:** `ACADEMIC`, method
  `ACADEMIC_ALIGNMENT_V01` version `1`, `HYBRID`; allowed sources are explicit
  student academic intent, authoritative curriculum facts, student coursework
  as alignment context, active taxonomy concepts, and active verified
  student/catalog mappings.
- **B. Required inputs:** declared academic intent and selected `KNOWN`
  `PROGRAM_COURSE.course_name` or `official_description` curriculum evidence,
  each represented by exact manifest items and `INCLUDED` required states.
- **C. Deterministic comparisons:** desired/excluded taxonomy targets versus
  reviewed curriculum classifications; required course/thesis/research
  structure only where an exact allowed canonical fact exists. Unsupported
  structure comparisons return `UNKNOWN`.
- **D. Reviewed mapping use:** only active `VERIFIED`
  `FIELD_CLASSIFICATION`, `SUBFIELD_CLASSIFICATION`,
  `SUBJECT_CLASSIFICATION`, `COURSE_EQUIVALENCY`, and
  `STUDENT_COURSE_EQUIVALENCY` relations; their frozen assessment permissions
  apply and none independently permits `STRONG_ALIGNMENT`.
- **E. Model permission:** the frozen registry permits subordinate,
  version/build-pinned, evidence-linked model signals. The pure core v0.1 does
  not call a model or accept a generic model payload; until a separate exact
  typed inference-artifact contract exists, it emits no model-derived direction.
  Model evidence could never create facts, grant mapping authority, override
  deterministic contradiction, or alone produce `STRONG_ALIGNMENT`/`HIGH`.
- **F. Material supports:** authoritative curriculum directly supporting an
  explicit study goal or active reviewed mappings showing material subject
  overlap.
- **G. Material contradictions:** authoritative required curriculum conflicting
  with an explicit exclusion, or sufficiently covered evidence establishing
  absence of a strongly desired direction under section 4.0; silence, sparse
  curriculum, or a missing mapping never establishes absence.
- **H. `REQUIRED` precedence:** a directly comparable deterministic
  contradiction tied to authoritative `REQUIRED` academic intent forces
  `MISALIGNMENT`; unknown/incomparable facts force `UNKNOWN`.
- **I. `STRONG_ALIGNMENT`:** permitted only through
  `DIRECT_HIGH_IMPORTANCE_AUTHORITATIVE_MATCH`, with `REQUIRED` or
  `STRONGLY_PREFERRED` intent, selected authoritative curriculum evidence, a
  qualifying non-model signal, and no material contradiction.
- **J. `UNKNOWN`:** missing/unspecified intent, missing required curriculum,
  unresolved or non-authoritative mapping, stale/conflicting fact, or evidence
  unable to establish direction.
- **K. Confidence:** `HIGH` requires qualifying non-model authoritative
  direction; mapping/model limitations lower confidence and model-only
  direction can never be `HIGH`.
- **L. Coverage:** required intent and curriculum must be usable;
  student-course context is optional; missing evidence that could reverse the
  direction makes coverage `INSUFFICIENT` and assessment `UNKNOWN`.
- **M. Prohibited inputs:** GPA, grades as capability signals, GRE/GMAT,
  prerequisite satisfaction, Eligibility decisions/gaps, competitiveness,
  admission probability, prestige/ranking, costs, location, international
  access, and employment probability.

### 4.2 Career Alignment

- **A. Permitted categories:** `CAREER`, method `CAREER_ALIGNMENT_V01` version
  `1`, `HYBRID`; explicit career intent, career-relevant curriculum, verified
  mappings, active career concepts, and selected reviewed career context.
- **B. Required inputs:** declared career intent and an active verified
  career/industry mapping under the required frozen policy.
- **C. Deterministic comparisons:** explicit role/industry target versus an
  active reviewed relation; required experiential format only against an exact
  allowed canonical program fact. No outcome probability calculation.
- **D. Reviewed mapping use:** active `VERIFIED` `CAREER_ASSOCIATION` and
  `INDUSTRY_ASSOCIATION` may support all non-strong states;
  `PROGRAM_RELATED_TO_CAREER` may support only `ALIGNMENT`, `MIXED`, or
  `UNKNOWN` and is not proof of preparation.
- **E. Model permission:** the registry permits a pinned subordinate model
  signal where policy allows, but core v0.1 neither calls a model nor accepts a
  generic model payload. Until a separate exact typed inference artifact is
  approved, it emits no model-derived direction. A title, similarity, or model
  hypothesis could never become a verified mapping, authoritative outcome,
  `HIGH` confidence, or `STRONG_ALIGNMENT`.
- **F. Material supports:** three evidence families remain distinct through
  interpretation and reason construction: (1) career-relevant curriculum is
  indirect content relevance and can support only when an active reviewed
  career/industry mapping connects it to the explicit target; (2) a reviewed
  program-career association establishes contextual relationship, not
  preparation or outcomes; and (3) observed outcomes are population-, program-,
  geography-, period-, and sample-specific corroboration, never causal proof or
  employment probability. Curriculum relevance is ordinarily weak-to-medium;
  reviewed association is medium when exact and applicable; observational
  outcomes are corroborative and capped at medium regardless of sample size.
  These families may corroborate one another but may not be collapsed into one
  generic "career evidence" fact or promoted across authority levels.
- **G. Material contradictions:** sufficiently applicable reviewed
  program-level evidence contradicting a target role/industry/geography, or a
  known absent required career-path feature under section 4.0; missing
  mappings, unreported outcomes, and title/curriculum silence are limiting
  evidence only.
- **H. `REQUIRED` precedence:** a directly comparable deterministic
  contradiction of a `REQUIRED` career feature forces `MISALIGNMENT`; an
  indirect or unknown absence returns `UNKNOWN`.
- **I. `STRONG_ALIGNMENT`:** not permitted by the frozen v0.1 method, even if
  multiple positive signals exist.
- **J. `UNKNOWN`:** missing intent/mapping, title-only or model-only linkage,
  sparse outcome evidence, wrong program/population/geography/period, or
  unresolved conflicts.
- **K. Confidence:** authority and applicability govern confidence under the
  explicit section 6 table. Any conclusion materially dependent on observed
  outcomes is capped at `MEDIUM`; Career v0.1 is observational overall and can
  never exceed `MEDIUM`. Model involvement also caps it at `MEDIUM`, and
  model-only direction is `LOW`/`UNKNOWN`.
- **L. Coverage:** intent and required verified mapping must be included;
  optional curriculum/context can support a bounded result, but material
  applicability gaps that could reverse direction require `INSUFFICIENT` and
  `UNKNOWN`.
- **M. Prohibited inputs:** marketing/name as proof, unreviewed similarity,
  institution-wide outcomes as program outcomes, salary/employment
  probability, competitiveness, admission probability, international work
  authorization, affordability, prestige/ranking, and general location
  preference.

### 4.3 Financial Alignment

- **A. Permitted categories:** `FINANCIAL`, method
  `FINANCIAL_ALIGNMENT_V01` version `1`, `DETERMINISTIC`; typed financial
  intent, selected canonical cost facts, completeness, and verified
  evaluation-scoped normalization artifacts.
- **B. Required inputs:** one or more exact typed financial intents, evaluated
  independently by semantic type, and selected `KNOWN` cost components with
  amount, currency, billing basis, period, scope, basis, and components
  sufficient for each attempted comparison.
- **C. Deterministic comparisons:** compare exact decimals only when currency,
  period, scope, gross/net basis, and components match; otherwise require a
  pinned verified normalization artifact with conversion evidence.
- **D. Reviewed mapping use:** none; taxonomy/context mapping relations do not
  authorize Financial v0.1 decisions. A normalization is a verified derivation,
  not a mapping.
- **E. Model permission:** none for financial intent, program cost, or
  normalization decision inputs in the frozen method.
- **F. Material supports:** comparable sufficiently complete cost within a
  preferred/hard ceiling. `AVAILABLE_FUNDING` may contribute only as a
  separately evidenced resource in an exact compatible comparison or through
  an approved normalization that produces
  `NET_OF_VERIFIED_FUNDING`; it is not itself a budget or alignment threshold.
- **G. Material contradictions:** comparable sufficiently complete cost above
  a ceiling, or a known required payment/cash-flow obligation breaching a
  separately declared hard cash-flow or cost constraint. Cost exceeding an
  `AVAILABLE_FUNDING` declaration alone is not a contradiction because funding
  is not necessarily exhaustive.
- **H. `REQUIRED` precedence:** a direct comparable breach of a
  student-authorized `REQUIRED` hard ceiling forces `MISALIGNMENT`; positive
  funding cannot override unless already represented in the same verified net
  basis.
- **I. `STRONG_ALIGNMENT`:** not permitted by the frozen v0.1 method.
- **J. `UNKNOWN`:** unspecified budget, incompatible currency/period/scope/
  basis/components, incomplete reversible costs or aid, unresolved gross/net
  basis, required normalization without an approved artifact, or any attempt
  to use `AVAILABLE_FUNDING` as exhaustive resources without an exact
  student-authorized contract that v0.1 does not define.
- **K. Confidence:** `HIGH` is available only for exact authoritative
  deterministic comparisons with complete material provenance; partial or
  normalized evidence follows explicit method limitations.
- **L. Coverage:** all comparison-defining fields and material components must
  be known for `SUFFICIENT`; decisive but bounded known mismatch may be
  `PARTIAL`; reversible missingness is `INSUFFICIENT` and `UNKNOWN`.
- **M. Prohibited inputs:** tuition treated as total cost, invented exchange
  rates/living cost/aid/family funding/future income, unlike bases, speculative
  ROI, career outcomes, salary, ranking, competitiveness, or admission
  probability.

`AVAILABLE_FUNDING` has one meaning: a known resource amount with its declared
currency, period, scope, basis, and components. It is distinct from
`HARD_TOTAL_COST_CEILING`, `PREFERRED_TOTAL_COST`,
`HARD_TUITION_CEILING`, and `PREFERRED_TUITION`; importance does not transform
one semantic type into another. It may be used only to (a) evidence a resource
component, (b) participate in an exact like-for-like cash-flow comparison when
a separate hard constraint supplies the decision threshold, or (c) support an
approved, evidence-linked gross-to-`NET_OF_VERIFIED_FUNDING` normalization.
It may not independently define maximum willingness to pay, total available
resources, expected aid, a hard ceiling, an offset across unlike
period/scope/components, or a contradiction. Unknown aid or other funding is
never treated as zero.

Multiple financial intents do not collapse into a single threshold. A
satisfied hard ceiling contributes method-valid support for that ceiling; a
contradicted comparable preferred-cost intent contributes a separate material
contradiction. With both present, the Financial result is `MIXED`, not
`ALIGNMENT`, because hard-ceiling satisfaction does not erase preference.
`AVAILABLE_FUNDING` remains a separate resource semantic and never masks,
weakens, satisfies, or rewrites `PREFERRED_TOTAL_COST` or `PREFERRED_TUITION`.
Only a verified like-for-like net-basis normalization may change the compared
cost basis, and the preferred intent is still evaluated against that explicit
basis.

> **Financial persistence resolution:** migration `011` lines implementing
> normalization validation and finalizer comparability force
> `original_period/financial_period = ACADEMIC_YEAR` and
> `original_basis/financial_basis = GROSS`, but never translate or validate
> `program_costs.billing_basis`. Because `TOTAL_PROGRAM`, `PER_SEMESTER`, and
> `PER_CREDIT` are not safely equivalent to `ACADEMIC_YEAR`, Financial v0.1
> cannot be implemented against the frozen finalizer. The only acceptable
> resolution is an approved additive migration `012+` with corresponding
> contract/test updates. Migration `014` is that approved additive resolution;
> application code must use its typed v014 contract and may not fall back to
> the legacy assumption.

### 4.4 Geographic/Delivery Alignment

- **A. Permitted categories:** `GEOGRAPHIC_DELIVERY`, method
  `GEOGRAPHIC_DELIVERY_ALIGNMENT_V01` version `1`, `HYBRID`; explicit
  location/delivery intent and selected canonical program facts. The frozen
  program-field allowlist currently exposes `delivery_mode`.
- **B. Required inputs:** declared geographic/delivery intent and an exact
  selected `KNOWN` fact authorized by the required location/delivery policy.
  A location-only request without an authorized exact location fact returns
  the explicit partial-unknown case below.
- **C. Deterministic comparisons:** desired/excluded delivery mode versus
  canonical `delivery_mode`. Location comparison is permitted semantically
  only when a future version adds an exact authorized location field; v0.1
  cannot fabricate it.
- **D. Reviewed mapping use:** no mapping relation is registered for this
  method in frozen v0.1.
- **E. Model permission:** the registry allows subordinate interpretation over
  supplied authorized facts, but core v0.1 does not call a model or accept a
  generic model payload. It emits no model-derived direction without a later
  exact typed inference artifact; a model could never infer preference, create
  a location fact, or override a direct delivery contradiction.
- **F. Material supports:** canonical delivery directly satisfying explicit
  desired/required delivery intent.
- **G. Material contradictions:** canonical delivery directly conflicting with
  an excluded or required delivery constraint. No unsupported geographic
  recruiting claim may become directional.
- **H. `REQUIRED` precedence:** a direct deterministic `REQUIRED` delivery
  contradiction forces `MISALIGNMENT`; missing/imprecise program location or
  delivery produces `UNKNOWN` unless an independently decisive direct delivery
  contradiction applies.
- **I. `STRONG_ALIGNMENT`:** not permitted by the frozen v0.1 method.
- **J. `UNKNOWN`:** unspecified intent, unavailable exact location field,
  `UNKNOWN`/stale/conflicting delivery, or indirect/conflicting geographic
  context.
- **K. Confidence:** direct selected delivery comparison may support `HIGH`
  under method rules; inferred or incomplete geography cannot.
- **L. Coverage:** required intent and exact relevant program fact are needed.
  Because frozen Phase 1 exposes `delivery_mode` but no exact location field, a
  supplied location intent with usable delivery evidence is explicitly
  accepted as assessment `UNKNOWN`, coverage `PARTIAL`, with
  `PROGRAM_FACT_UNKNOWN`; it is not an invalid DTO and geography is not
  fabricated. If no relevant usable fact exists at all, coverage is
  `INSUFFICIENT`. A decisive direct required-delivery contradiction may remain
  `MISALIGNMENT` with `PARTIAL` coverage.
- **M. Prohibited inputs:** nationality/demographic preference inference,
  institutional location as labor-market proof, visa/work authorization,
  Eligibility, cost, career-outcome probability, prestige/ranking, and inferred
  culture.

### 4.5 Personal Preference Alignment

- **A. Permitted categories:** `PERSONAL_PREFERENCE`, method
  `PERSONAL_PREFERENCE_ALIGNMENT_V01` version `1`, `HYBRID`; explicit duration
  or allowlisted feature intent, selected `duration_months`, `full_time`, or
  `capstone_required`, and completeness.
- **B. Required inputs:** explicit program-characteristic intent and the exact
  selected observable characteristic needed for comparison.
  DTO validation rejects, before evaluation, any purported Personal Preference
  intent semantically owned by Financial, Geographic/Delivery, Career,
  International Accessibility, or Eligibility. Importance or a user-facing
  "preference" label never changes dimension ownership.
- **C. Deterministic comparisons:** duration bounds versus
  `duration_months`; full-time or capstone expectation versus the corresponding
  boolean fact. Other structures return `UNKNOWN` unless exactly authorized in
  a later version.
- **D. Reviewed mapping use:** no mapping relation is registered to authorize a
  Personal Preference v0.1 result, even though taxonomy sources remain
  generally classified.
- **E. Model permission:** the registry permits subordinate interpretation of
  allowed supplied facts, but core v0.1 does not call a model or accept a
  generic model payload. It emits no model-derived direction without a later
  exact typed inference artifact and could never infer personality/
  psychographics or create an unrepresented characteristic.
- **F. Material supports:** an observable allowlisted characteristic satisfying
  explicit intent.
- **G. Material contradictions:** an observable allowlisted characteristic
  directly conflicting with explicit intent; multiple non-required conflicts
  may be material under the method.
- **H. `REQUIRED` precedence:** a direct deterministic duration contradiction
  tied to `REQUIRED` intent forces `MISALIGNMENT`. Delivery remains owned by
  Geographic/Delivery in the frozen typed intent contract.
- **I. `STRONG_ALIGNMENT`:** not permitted by the frozen v0.1 method.
- **J. `UNKNOWN`:** unspecified intent, stale/unknown fact, unsupported feature,
  or missing exact characteristic.
- **K. Confidence:** direct selected observable comparison can support higher
  confidence; inferred interpretation, missing optional context, or stale facts
  reduce it.
- **L. Coverage:** required intent and compared fact must be included;
  unsupported/unavailable material characteristics make coverage
  `INSUFFICIENT` and assessment `UNKNOWN`.
- **M. Prohibited inputs:** inferred personality, culture, social comfort,
  learning style, demographic proxies, prestige, probability,
  competitiveness, and duplicate ownership of financial, geographic, career,
  international-access, or Eligibility judgments.

### 4.6 International Accessibility

- **A. Permitted categories:** `INTERNATIONAL_ACCESSIBILITY`, method
  `INTERNATIONAL_ACCESSIBILITY_V01` version `1`, `HYBRID`; explicit target
  intent, authorized student access context, selected `stem_status`, active
  path concepts, current verified regulatory/accessibility claims, and active
  verified context mappings.
- **B. Required inputs:** declared international target path and a pinned
  selected `KNOWN`, `VERIFIED`, `OFFICIAL_REGULATORY` context observation under
  the required policy; high-impact direction also requires matching authorized
  student access context.
- **C. Deterministic comparisons:** verified current licensing/geographic/
  authorization restriction versus explicit profession, jurisdiction, timing,
  and path. `stem_status` alone is never deterministic alignment.
- **D. Reviewed mapping use:** active `VERIFIED`
  `PROGRAM_ASSOCIATED_WITH_PATH` and `CLAIM_APPLIES_TO_CONCEPT`, subject to
  their allowed non-strong assessments and a selected verified underlying
  claim.
- **E. Model permission:** the registry permits pinned limiting/subordinate
  model signals, but core v0.1 does not call a model or accept a generic model
  payload. It emits no model-derived direction without a later exact typed
  inference artifact. Model-only evidence could never produce high-impact
  direction, `HIGH` confidence, verified authority, or `STRONG_ALIGNMENT`.
- **F. Material supports:** current non-model authoritative structural evidence
  applicable to the exact student jurisdiction/path/program and showing
  access without a known material restriction.
- **G. Material contradictions:** current applicable licensing, clearance,
  authorization, sponsorship, or geographic restriction conflicting with the
  explicit path.
- **H. `REQUIRED` precedence:** a directly comparable current authoritative
  restriction against a `REQUIRED` path forces `MISALIGNMENT`; stale,
  wrong-jurisdiction, or incomparable evidence returns `UNKNOWN`.
- **I. `STRONG_ALIGNMENT`:** not permitted by the frozen v0.1 method.
- **J. `UNKNOWN`:** missing target/access context, STEM-only evidence,
  stale/wrong-population/wrong-jurisdiction/wrong-period/wrong-path evidence,
  generic outcomes, or model-only high-impact evidence.
- **K. Confidence:** depends on current authority and exact applicability;
  model, observational, indirect, or scope-limited evidence lowers confidence,
  and model-only direction cannot be `HIGH`.
- **L. Coverage:** target path and required regulatory evidence must be
  included; high-impact direction needs applicable access context and complete
  scope. A missing applicability key that could reverse direction is
  `INSUFFICIENT` and `UNKNOWN`.
- **M. Prohibited inputs:** admission Eligibility, prerequisites, application
  documents, language/admission requirements, applicant-category policy,
  admission/visa/employment probability, STEM as automatic fit, generic
  outcomes, Career/Geographic judgments, unsupported legal advice, GPA/GRE/
  GMAT, prestige/ranking, and competitiveness.

## 5. Signal combination and precedence

Each dimension method first validates evidence against its
`ResolvedFitContract` and owns all semantic judgments. Only then may the
sharply restricted `combine-signals.ts` accept only a validated boolean
projection from `DimensionEvidenceInterpretation`; it must not receive raw
signals, reasons, evidence, policies, relations, authority labels, or manifest
items. Its complete decision table is:

1. `hasRequiredConstraintContradiction` → `MISALIGNMENT`;
2. otherwise `hasMaterialSupport && hasMaterialContradiction` → `MIXED`;
3. otherwise `hasMaterialContradiction` → `MISALIGNMENT`;
4. otherwise `hasQualifiedStrongAlignment && hasMaterialSupport` →
   `STRONG_ALIGNMENT`;
5. otherwise `hasMaterialSupport` → `ALIGNMENT`;
6. otherwise → `UNKNOWN`.

Validation rejects impossible boolean shapes, including qualified strong
alignment without support, required contradiction without material
contradiction, or any true directional boolean when
`hasDirectionalBasis=false`, and a true directional basis with no support,
contradiction, or qualified strong alignment. As an optional implementation
optimization, the combiner may be an exhaustive inline pure function rather
than a separate
module, provided its boolean-only signature and independent truth-table tests
remain intact.

`combine-signals.ts` never inspects or decides materiality, direction,
comparability, absence, signal validity, `requiredConstraintContradiction`,
strong-alignment qualification, confidence, coverage, applicability, evidence
authority, identities, or reason selection. A dimension method alone may qualify
`STRONG_ALIGNMENT` against its exact registered method/signal contract; the
combiner may only preserve the already-validated boolean when precedence finds
no contradiction, and must never derive qualification from signal counts.

Missing evidence is limiting, not contradicting. `NEUTRAL` is student intent;
`UNKNOWN` is an assessment. Input order, duplicate evidence, or presentation
text must not influence the result.

## 6. Evidence coverage and confidence

Coverage is computed per pinned method from declared required and optional
input policies:

- `SUFFICIENT`: all evidence required for the conclusion is included,
  applicable, authoritative where required, and usable;
- `PARTIAL`: some declared evidence is unavailable, but decisive applicable
  evidence still supports a bounded conclusion;
- `INSUFFICIENT`: the core question lacks usable evidence; assessment must be
  `UNKNOWN`.

A non-`INCLUDED` required input forces `UNKNOWN`. Missing optional evidence
does not automatically block a conclusion. If missing evidence could reasonably
reverse direction, coverage is insufficient and the result is `UNKNOWN`.

Confidence is owned by each dimension method:

- `HIGH` requires the method's explicit high-confidence conditions and at
  least one material non-model directional signal;
- `MEDIUM` represents a defensible bounded result with declared limitations;
- `LOW` represents substantial uncertainty in a still-permitted conclusion or
  an `UNKNOWN` result.

There is no universal `coverage → confidence` formula. Coverage and confidence
must each produce structured reasons. Neither may be numeric or described as a
probability.

Shared coverage/confidence utilities may only detect contract-independent
facts, such as the presence of a declared non-`INCLUDED` state, whether all
directional signals are model-derived, or whether an exact provenance
reference exists. They return facts, never `FitCoverage` or `FitConfidence`.
Only the owning method interprets those facts and assigns categorical coverage
and confidence under its resolved registry contract.

### 6.1 Per-method confidence decision tables and ceilings

These are ordered, fail-closed decision tables. The first matching row applies;
all rows also require exact provenance, applicability, and a contract-valid
assessment. Across every method, any material model involvement caps confidence
at `MEDIUM`; model-only direction is `LOW` with assessment `UNKNOWN`.

**Academic `ACADEMIC_ALIGNMENT_V01`**

- `HIGH`: direct selected official curriculum facts or verified mappings
  provide non-model material direction, all decisive scope is included, and no
  material applicability or authority limitation remains.
- `MEDIUM`: direction is defensible but depends on reviewed mapping, incomplete
  optional context, bounded scope, or any permitted model involvement.
- `LOW`: no authoritative directional basis, unresolved mapping/absence,
  reversible missingness, or assessment `UNKNOWN`.

**Career `CAREER_ALIGNMENT_V01` — ceiling `MEDIUM`**

- `HIGH`: never permitted in v0.1; Career evidence is observational,
  associative, or indirect rather than causal.
- `MEDIUM`: exact explicit career intent plus a verified applicable
  career/industry or program-career association supports a bounded conclusion;
  applicable observed outcomes may corroborate but never raise the ceiling.
- `LOW`: title-only, curriculum without the required reviewed connection,
  sparse/inapplicable outcomes, model-only direction, unresolved conflict, or
  assessment `UNKNOWN`.

**Financial `FINANCIAL_ALIGNMENT_V01`**

- `HIGH`: every independently material financial intent has an exact,
  authoritative, complete, like-for-like deterministic comparison, including
  currency, period, scope, basis, components, and any verified normalization.
- `MEDIUM`: a bounded decisive comparison remains valid despite declared
  non-reversing optional gaps or a verified normalization whose registered
  contract imposes a limitation.
- `LOW`: incompatible bases, unknown reversible cost/funding, unsupported
  normalization, unresolved multiple-intent interaction, or assessment
  `UNKNOWN`. Implementation uses the additive Migration `014` billing-basis
  contract and never the legacy Migration `011` assumption.

**Geographic/Delivery `GEOGRAPHIC_DELIVERY_ALIGNMENT_V01`**

- `HIGH`: direct selected official `delivery_mode` exactly determines the
  supplied delivery-only intent with no unresolved geographic component.
- `MEDIUM`: direct delivery direction is bounded by non-reversing optional
  context or permitted model involvement.
- `LOW`: a location intent lacks an exact authorized Phase 1 location field,
  delivery is stale/conflicting, or assessment is `UNKNOWN`; the accepted
  location case is coverage `PARTIAL`, confidence `LOW`.

**Personal Preference `PERSONAL_PREFERENCE_ALIGNMENT_V01`**

- `HIGH`: direct selected official `duration_months`, `full_time`, or
  `capstone_required` exactly resolves every in-scope intent with no limitation.
- `MEDIUM`: direct direction has non-reversing optional gaps or permitted model
  involvement.
- `LOW`: unsupported characteristic, missing/stale/conflicting observable,
  ownership violation, model-only direction, or assessment `UNKNOWN`.

**International Accessibility `INTERNATIONAL_ACCESSIBILITY_V01`**

- `HIGH`: direct current `OFFICIAL_REGULATORY`, non-model evidence exactly
  matches student context, jurisdiction, population, program, path, and
  validity period and directly establishes direction.
- `MEDIUM`: defensible direction lacks direct official regulatory proof,
  depends on reviewed mapping/indirect evidence, has a bounded applicability
  limitation, or includes any permitted model involvement. This is the maximum
  without direct official regulatory evidence.
- `LOW`: evidence is stale, wrong-scope, model-only, STEM-only, materially
  incomplete, or otherwise cannot establish direction; assessment is
  `UNKNOWN`. When absence of direct official evidence leaves high-impact
  direction unsupported, the result must be `UNKNOWN`, never a confident
  alignment or contradiction.

## 7. Reasons, signals, and limiting information

The engine may emit only reason codes registered to the pinned Fit contract and
compatible with the assessment and direction. The initial normalized set
includes:

- `STUDENT_PREFERENCE_UNSPECIFIED`
- `REQUIRED_INPUT_UNAVAILABLE`
- `MATERIAL_EVIDENCE_SUPPORTS_ALIGNMENT`
- `MATERIAL_EVIDENCE_CONTRADICTS_INTENT`
- `REQUIRED_CONSTRAINT_CONTRADICTED`
- `MODEL_INFERENCE_LIMITATION`
- `SOURCE_CONFLICT`
- `FINANCIAL_INPUTS_INCOMPARABLE`
- `INTERNATIONAL_EVIDENCE_INAPPLICABLE`
- `STUDENT_INPUT_INCOMPLETE`
- `PROGRAM_FACT_UNKNOWN`
- `STALE_SOURCE`
- `NO_AUTHORITATIVE_MAPPING`
- `EVIDENCE_INSUFFICIENT`
- `METHOD_UNSUPPORTED`
- `INPUT_INAPPLICABLE`
- `INTENT_CONFLICT`

Every material signal requires exact evidence references and the exact intent
it evaluates. Every dimension result requires at least one structured reason.
Every `UNKNOWN` requires a limiting reason tied to a non-included input state
or an evidence-linked limiting signal.

Core v0.1 does not generate prose and has no prose field in its output DTOs.
Any human-readable explanation belongs to an outer presentation layer with its
own contract. That layer may render only the structured reason/signal/limiting
data; its prose is not core output and is excluded from decision and result
fingerprints.

## 8. Deterministic replay contract

Before evaluation, canonicalization must:

- validate closed-union values and schema version;
- reject duplicate source references within a method and source type;
- sort dimensions by canonical enum order;
- sort methods, policies, intents, evidence, components, signals, evidence
  links, and reasons by stable semantic keys;
- preserve exact identifiers and pinned versions;
- avoid locale-sensitive comparison, floating-point arithmetic, current time,
  random values, generated identifiers, and object insertion order.

The engine receives `evaluationAsOf`; it never reads the clock. Numeric
financial values use exact decimal strings or a decimal implementation, never
binary floating-point. Core v0.1 neither calls a model nor accepts an untyped
precomputed model payload. A future model inference artifact requires a closed,
fingerprinted input contract before the core may consume it.

Replay acceptance:

- reordered equivalent input is deep-equal after canonicalization;
- repeated evaluation is deep-equal;
- mutation of an exact evidence ID, mapping state, method version, intent,
  applicability field, or input availability changes canonical decision input;
- presentation prose is absent from core input/output and excluded from all
  fingerprints;
- post-finalization database fingerprint recomputation must match the sealed
  candidate input.

## 9. Persistence adapter and SQL finalizer boundary

The future adapter/resolver performs mechanical translation only:

1. Load the exact pinned verified Fit release and evaluator build, six methods,
   materiality contracts, input policies, source/field allowlists, mapping
   relations, signal types, reasons, financial normalizations, frozen
   profile/intent snapshots, exact allowed evidence, and explicit availability
   states.
2. Mechanically produce `ResolvedFitContract` and reject any identity or
   semantic drift; do not supply defaults, aliases, or inferred policy.
3. Construct and validate `FitEvaluationInput` without Eligibility decision
   data and require exact compatibility among its release ID/digest, resolved
   registry graph, evaluator build authorization, six method pins, policy IDs,
   and all manifest/input-state registry references.
4. Call the pure engine.
5. Start a `BUILDING` evaluation and obtain exact build-scoped assembly
   authorization.
6. Persist typed manifest items, input states, six results, signals, signal
   evidence, and reasons exactly as emitted.
7. Call `seal_fit_evaluation_inputs(evaluation_id)`.
8. Call `finalize_fit_evaluation(evaluation_id)`.
9. Treat SQL rejection as a failed evaluation; never patch the output or
   downgrade constraints in the adapter.

The engine proposes a contract-conforming decision; PostgreSQL remains the
final integrity authority. The adapter must not duplicate decision logic,
compute an aggregate, include Eligibility in the decision manifest, mutate
upstream facts, or directly mark an evaluation `COMPLETED`.

The database registry remains the sole semantic authority throughout this
boundary. Resolver output is a lossless persistence-neutral projection of that
authority, not a second registry. If registry state at persistence differs
from the exact identity graph evaluated by the engine, assembly/finalization
must fail closed and the evaluation must be rebuilt against a newly resolved
contract; the adapter may not translate between identities.

## 10. Test plan

### 10.1 Pure engine contract tests

- exactly six keys, no omission and no extra dimension;
- one fixture where all six dimensions return `UNKNOWN`, each with a structured
  limiting input and exact manifest provenance;
- ordinary accepted fixtures for `ALIGNMENT`, Academic
  `STRONG_ALIGNMENT`, `MIXED`, and `MISALIGNMENT`;
- exhaustive closed-union handling;
- no aggregate score/rank/probability fields at runtime or type level;
- no Eligibility field in input, output, dimension decision, signal, or reason;
- input immutability: deep-freeze the exact manifest and prove evaluation does
  not mutate any nested value or array;
- deterministic replay: repeated evaluation of the same frozen input produces
  byte-equivalent canonical output;
- insertion-order independence: every manifest, input-state, component,
  mapping, and evidence-link permutation produces the same canonical output;
- same raw evidence reuse: one immutable source legitimately manifested for two
  dimensions through two method-specific refs is evaluated independently and
  never cross-links signals/reasons;
- duplicate exact manifest membership is rejected;
- unsupported schema/method/reason/signal fails closed;
- exact pinned registry identity compatibility: release ID/code/version/digest,
  evaluator build, six method IDs/versions, policy IDs, signal-type IDs,
  reason-definition IDs, mapping relation identities, normalization identities,
  and canonical semantic payloads must match the verified fixture exactly;
- registry drift mutations (missing/extra/retired/unverified/wrong-release
  members or changed materiality, direction, requirement, allowlist,
  applicability, strong permission, or allowed assessment) fail before
  evaluation and never fall back to package constants;
- complete-projection fixtures prove no release/build lifecycle guardrail,
  source-class definition/disposition, field tuple, mapping relation policy,
  signal/reason policy, verification identity, or normalization payload can be
  omitted;
- exact method/policy/signal/reason/relation IDs survive input,
  interpretation, output, persistence translation, and replay unchanged;
- Personal Preference DTO construction rejects semantics owned by every other
  dimension before evaluation.

### 10.2 Dimension tests

- every allowed, forbidden, deterministic, inference, `MIXED`,
  `MISALIGNMENT`, and `UNKNOWN` case from sections 5.1–5.6 of the semantic
  specification;
- exact frozen method code/category/strong-alignment permission;
- required versus optional policy behavior;
- source-class, field, mapping relation, and applicability boundaries;
- strict absence cases for every dimension; in particular, missing Academic
  curriculum/mappings and missing Career mappings/outcomes are `UNKNOWN`, not
  contradictions, unless exact authoritative closed-world absence proof
  satisfies a method-declared closed observable `COMPLETE` domain; prove the
  frozen v0.1 registry currently declares no such domain;
- Career fixtures independently vary curriculum relevance, reviewed
  program-career association, and applicable observed outcomes and prove they
  retain distinct semantics, authority, and strength;
- financial exact-decimal and normalization behavior;
- multiple comparable Financial intents: satisfied hard ceiling plus
  contradicted preferred cost produces `MIXED`; funding never masks the
  preferred-cost contradiction;
- `AVAILABLE_FUNDING` versus `HARD_TOTAL_COST_CEILING`: prove funding is not a
  ceiling, preferred cost, exhaustive-resource declaration, or contradiction;
  a ceiling is not funding; and funding offsets cost only through an exact
  compatible comparison with a separate hard threshold or the same verified
  `NET_OF_VERIFIED_FUNDING` basis;
- location intent without an exact Phase 1 location field produces the explicit
  `UNKNOWN`/`PARTIAL`/`LOW` result while preserving any delivery evidence;
- international jurisdiction, population, validity, program, and path matching.

### 10.3 Combination, confidence, and coverage tests

- support only → `ALIGNMENT`;
- contradiction only → `MISALIGNMENT` when method-valid;
- material support plus contradiction → `MIXED`;
- missing evidence only → `UNKNOWN`, never `MIXED`;
- direct deterministic `REQUIRED` contradiction overrides positive signals;
- unknown/incomparable required fact → `UNKNOWN`, not `MISALIGNMENT`;
- `INSUFFICIENT` coverage only with `UNKNOWN`;
- model-only direction never `HIGH`;
- every method's `HIGH`/`MEDIUM`/`LOW` decision table and ceiling is exhaustive;
  Career never exceeds `MEDIUM`, any model-involved conclusion never exceeds
  `MEDIUM`, and International without direct official regulatory evidence is
  at most `MEDIUM` or must be `UNKNOWN`;
- no universal coverage/confidence conversion;
- shared utilities return detected facts only; mutating a method-owned
  confidence or coverage rule cannot be masked by a shared default;
- combiner accepts only validated booleans, rejects impossible boolean shapes,
  and cannot receive or derive raw signals, identities, materiality, direction,
  comparability, absence, strong qualification, confidence, or coverage;
- `DimensionEvidenceInterpretation` carries method-owned semantics and exact
  identities into the boolean-only combiner without semantic loss;
- Academic-only strong-alignment qualification under the frozen registry.

### 10.4 Adversarial boundary tests

- eligibility non-influence: vary adjacent Eligibility among `ELIGIBLE`,
  `NOT_ELIGIBLE`, and `UNKNOWN` outside the decision DTO while holding
  `FitEvaluationInput` fixed; output remains byte-equivalent;
- Eligibility leakage attempts: status, gaps, unknowns, rule results, and
  eligibility fingerprint cannot enter input, signals, reasons, confidence,
  coverage, or output;
- academic-capability leakage attempts: GPA, grades-as-strength, GRE, GMAT,
  generic derived features, and generic capability/quality scores;
- product leakage attempts: prestige/ranking, competitiveness, admission
  probability, acceptance likelihood, recommendation output/rank,
  Reach/Target/Safer, portfolio strategy, and aggregate/composite Fit;
- attempt model confidence as mapping authority;
- attempt proposed, rejected, retired, or wrong-relation mappings;
- attempt program title, marketing copy, or institution-wide outcomes as
  authoritative Career evidence;
- attempt tuition-only versus total budget, invented exchange rate, or
  mismatched period/scope/basis;
- attempt to reinterpret `AVAILABLE_FUNDING` as a hard ceiling, exhaustive
  resources, expected aid, or an independent contradiction, or apply it
  without a separate decision threshold and compatible exact comparison/
  verified net-basis normalization;
- attempt to use hard-ceiling satisfaction or funding to erase a contradicted
  preferred-cost intent;
- attempt to coerce `TOTAL_PROGRAM`, `PER_SEMESTER`, `PER_CREDIT`, or `UNKNOWN`
  `billing_basis` into migration `011`'s hard-coded `ACADEMIC_YEAR/GROSS`;
- attempt nationality-derived location preference;
- attempt STEM-only alignment, wrong jurisdiction, stale regulation,
  mismatched path, or model-only high-impact international direction;
- attempt personality or psychographic inference;
- attempt to label financial, geographic/delivery, career, international, or
  Eligibility intent as `PERSONAL_PREFERENCE`;
- attempt cross-dimension evidence ownership and cross-method evidence links;
- attempt unauthorized raw field exposure, generic structured evidence,
  unreferenced manifest values, duplicate refs, wrong policy/method ownership,
  and post-seal mutation;
- attempt generated presentation prose in core output or fingerprints;
- attempt hidden points, weighted voting, majority vote, aggregate score,
  ranking, probability, or Reach/Target/Safer labels;
- attempt to make the adapter/resolver, package constants, shared confidence/
  coverage utilities, or combiner a second semantic authority;
- attempt any registry identity substitution, semantic alias, permissive drift,
  or "closest compatible" fallback.

### 10.5 Replay and mutation tests

- permute every input collection;
- repeat evaluation with frozen clock input;
- replace exact evidence/mapping IDs with semantically similar records;
- mutate model version/build hash;
- mutate taxonomy, contract, method, profile, or intent pins;
- mutate source applicability and validity windows;
- prove all semantic mutations affect canonical input or output as expected;
- prove presentation-only changes do not alter assessment semantics.

### 10.6 Cross-layer SQL tests

For each accepted engine fixture, persist through the adapter, seal, and
finalize against migrations `001`–`011`. For each adversarial output, prove the
engine rejects it or `finalize_fit_evaluation` rejects it. The matrix must
cover:

- six-method pinning and six-result completeness;
- exact equality between the engine's `ResolvedFitContract` identity graph and
  the release/build/method/policy/signal/reason/normalization identities
  persisted and revalidated by SQL;
- stale, substituted, retired, or semantically drifted registry fixtures fail
  before assembly and cannot finalize;
- typed manifest subtype and policy ownership;
- source and field allowlists;
- active mapping and context authority;
- signal/evidence/reason ownership;
- combination, required-constraint, strong-alignment, confidence, and coverage
  invariants;
- financial comparability and international applicability;
- canonical decision/result fingerprints;
- post-seal mutation rejection;
- RLS owner/unrelated-user behavior;
- privacy deletion and intentional replay termination.

The Financial cross-layer gate is resolved by frozen Migration `014`, and
replay/finalization is hardened by frozen Migration `015`. The matrix must run
against `001`–`015`; legacy `001`–`011` behavior alone is not sufficient
evidence.

The existing baseline remains mandatory: clean migrations `001`–`011` PASS,
Phase 1 35 assertions PASS, Phase 2 SQL 32 assertions PASS, Phase 3 98
assertions PASS, Eligibility v0.1/v0.2 12/12 PASS, final post-build re-audit PASS,
and migrations `001`–`008` unchanged.

## 11. Implementation sequence and review gates

1. **Completed:** freeze Migration `014` resolving Phase 1 `billing_basis` and
   Migration `015` replay/seal integrity; re-run database consistency review.
2. **Completed:** approve this DTO and package-boundary design and authorize
   Fit Engine v0.1 implementation.
3. **Completed:** define fixture builders from frozen contract values without database
   imports.
4. **Completed:** implement canonical validation and replay ordering.
5. **Completed:** implement shared reason construction, fact detection, and restricted
   universal signal precedence primitives.
6. **Completed:** implement dimensions one at a time, beginning with deterministic Financial
   and Geographic/Delivery cases.
7. **Completed:** implement coverage and confidence rules per method.
8. **Completed:** add the exhaustive and adversarial pure-engine matrix.
9. **Completed:** add a separate persistence adapter.
10. **Completed:** run accepted and rejected fixtures through the SQL finalizer.
11. **Completed:** run the full established regression baseline and real Supabase integration
    checks.
12. **Completed:** register and verify the evaluator build after review evidence exists.
13. **Completed:** approve the separate overall Phase 3 documentation-and-hash
    freeze after all local and remote gates passed. No Git tag was created.

## 12. Blockers before implementation or release

Engine implementation guardrails:

- use the frozen Migration `014` Financial contract; do not reintroduce the
  Migration `011` `ACADEMIC_YEAR/GROSS` assumption;
- any unresolved mismatch between this plan, `PHASE_3_FIT_SPEC.md`, and frozen
  migrations `009`–`011`;
- any request to include Eligibility in a Fit decision DTO or fingerprint;
- any request for aggregate score, ranking, probability, or recommendation;
- any dimension rule not expressible by the frozen verified method, input,
  signal, reason, and mapping contracts;
- any proposed use of application logic to bypass a SQL finalizer invariant.

Consistency review disposition:

- **Resolved database defect:** migration `009` explicitly allowlists
  `PROGRAM_COST.billing_basis`; Phase 1 defines `TOTAL_PROGRAM`, `PER_YEAR`,
  `PER_SEMESTER`, `PER_CREDIT`, and `UNKNOWN`; migration `011`
  `validate_fit_financial_normalization()` nevertheless requires
  `original_period = ACADEMIC_YEAR` and `original_basis = GROSS`, and
  `finalize_fit_evaluation()` repeats `financial_period = ACADEMIC_YEAR` and
  `financial_basis = GROSS`. Neither path reads `program_costs.billing_basis`.
  The spec requires exact period/scope/basis comparability, so this is a
  contract/database defect, not a prose discrepancy or adapter detail.
  Migration `014` resolves it additively with independent billing-basis
  authority, typed conversion witnesses, funding isolation, and strict
  comparability; Migration `015` preserves its validation at seal.
- `PHASE_3_FIT_SPEC.md` sections 5.2–5.5 retain generic prose describing a
  possible `STRONG_ALIGNMENT` bar, while the verified v0.1 registry and
  `PHASE_3_DATABASE_FREEZE.md` permit it only for Academic. The engine follows
  the exact registry permission and cannot infer permission from the broader
  prose.
- semantic-spec MVP case 5 labels a delivery mismatch as Personal Preference,
  while migration `010` assigns `DELIVERY_CONSTRAINT` to
  `GEOGRAPHIC_DELIVERY`; the engine follows the typed registry/database
  ownership.
- the spec's short explanation and optional Eligibility-context language is
  satisfied only outside the core decision contract: migration `011` keeps
  optional presentation prose and display-only Eligibility context outside
  decision fingerprints, matching this plan's core exclusion.

The latter items are source-document prose discrepancies whose implementation
path is resolved by exact registry authority. The Financial mismatch required,
and has now received, additive migrations rather than an adapter default,
package constant, or narrowed fixture set.

Historical production release blockers at plan approval, all resolved by
[`PHASE_3_FREEZE.md`](PHASE_3_FREEZE.md):

- the TypeScript Fit engine is not yet implementation-frozen or released;
- no persistence adapter or cross-layer engine fixture suite currently exists;
- no production evaluator build is registered and verified;
- PostgreSQL 15 tests used a Supabase-compatible auth stub; full target
  Supabase Auth/RLS/service-role integration remains unverified;
- no API, operational monitoring, or deployment review exists;
- Phase 3 overall had not yet been frozen.

These items governed the original release gate and are retained as historical
design context; they no longer describe current project state.

## 13. Explicit exclusions

Fit engine v0.1 will not implement:

- an overall Fit conclusion or total/composite Fit Score;
- numeric dimension scores, weights, percentages, points, or votes;
- learned preference weights;
- program ranking or recommendation ranking;
- Reach/Target/Safer labels;
- Competitiveness;
- admission, visa, employment, salary, or success probability;
- portfolio or admissions strategy;
- Eligibility evaluation, reinterpretation, or influence;
- personality, psychographic, demographic-proxy, prestige, or generic-quality
  inference;
- unsupported career outcome, return-on-investment, immigration, or legal
  advice;
- source ingestion, canonical fact selection, mapping review, or model calls;
- changes to migrations `001`–`011`;
- a production API, UI, service, or deployment as part of the core-package
  milestone.

## 14. Milestone decision

The database contract is frozen separately in
[`PHASE_3_DATABASE_FREEZE.md`](PHASE_3_DATABASE_FREEZE.md), with later
hardening frozen through Migration `018`. This plan is **IMPLEMENTATION
COMPLETE**. The design makes the six
dimension boundaries, full registry projection, interpretation boundary,
combination semantics, uncertainty, provenance, replay, SQL finalizer boundary,
tests, guardrails, and exclusions explicit. Migration `014` resolves the prior
Financial period/basis defect and Migration `015` freezes replay integrity.
Implementation completed within this package boundary.

**Phase 3 Fit v0.1 is FROZEN by
[`PHASE_3_FREEZE.md`](PHASE_3_FREEZE.md). No Git tag was created by that
documentation-and-hash freeze.**
