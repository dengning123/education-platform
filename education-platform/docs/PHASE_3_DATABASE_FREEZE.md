# Phase 3 Fit Database Contract — FROZEN v0.1

Status: FROZEN DATABASE CONTRACT — **ENGINE NOT IMPLEMENTED**  
Database contract version: **Fit v0.1**  
Phase: **Phase 3 — Fit**  
Freeze date: **2026-08-20**  
Upstream contract: **`phase2-eligibility-v0.1`**

This record freezes only the Phase 3 Fit database and persistence contract
implemented by migrations `009`–`011`. It does not freeze Phase 3 overall.
There is no production Fit evaluator build, TypeScript Fit engine, API, final
Phase 3 release tag, score, ranking, probability, or recommendation system.

The authoritative semantic and database sources are:

1. [`PHASE_3_FIT_SPEC.md`](PHASE_3_FIT_SPEC.md), the Fit v0.1 semantic
   contract;
2. migrations `009`–`011`, the frozen executable database contract; and
3. `supabase/tests/003_phase3_fit.sql`, the verified database regression and
   adversarial suite.

If prose and executable persistence details appear to differ, no application
code may improvise a resolution. The semantic specification governs product
meaning; the frozen migrations govern persisted shape and enforcement. A real
conflict requires review and an additive, versioned change.

## 1. Frozen upstream boundary

The annotated tag `phase2-eligibility-v0.1` remains the immutable upstream
contract. Migrations `001`–`008` are unchanged.

Fit may reference exact Phase 1 catalog facts, frozen Phase 2 student data,
taxonomy records, reviewed mappings, and an optional pinned Eligibility
evaluation. Eligibility is display-only adjacent context. It is excluded from
Fit manifests, signals, reasons, decision fingerprints, and the Fit decision
contract. Changing `ELIGIBLE`, `NOT_ELIGIBLE`, or `UNKNOWN` alone must never
change a Fit assessment, confidence, or coverage.

## 2. Frozen migrations

- `202608200009_fit_contract_registry.sql`
  - freezes the six dimension identifiers and categorical enums;
  - defines contract, method, evaluator-build, source-class, mapping-relation,
    signal-type, input-policy, reason, and financial-normalization registries;
  - establishes per-method source and field allowlists and explicit prohibited
    classes, including Eligibility decisions, competitiveness, admission
    probability, prestige/ranking, recommendations, and generic capability
    scores;
  - preserves reviewed, versioned, append-only registry authority.
- `202608200010_fit_intents_and_context.sql`
  - freezes typed Fit intent snapshots over frozen profile versions;
  - requires explicit authority for `REQUIRED` importance and rejects
    conflicting or semantically invalid hard constraints;
  - defines typed taxonomy, location, delivery, financial, duration, and
    program-feature intent children;
  - keeps authorized international access context private;
  - defines versioned Phase 3 contextual claims, observations, canonical
    selections, reviewed mappings, applicability, and history.
- `202608200011_fit_evaluation_persistence.sql`
  - pins frozen profile and intent hashes, program version, taxonomy release,
    contract release, evaluator build, and exactly one method for every
    dimension;
  - stores typed exact manifest membership and explicit input availability;
  - stores one categorical result for each of the six dimensions;
  - stores governed signals, exact signal evidence, structured reasons, and
    evaluation-scoped financial normalization artifacts;
  - seals canonical input and result fingerprints;
  - enforces controlled finalization, append-only completed results, RLS,
    ownership, and privacy deletion.

These migrations are historical artifacts. They must not be edited, reordered,
squashed, or replaced after this database freeze.

## 3. Frozen database semantics

Every completed evaluation has exactly one result for each canonical
dimension:

- `ACADEMIC`
- `CAREER`
- `FINANCIAL`
- `GEOGRAPHIC_DELIVERY`
- `PERSONAL_PREFERENCE`
- `INTERNATIONAL_ACCESSIBILITY`

Every result has exactly one assessment:

- `STRONG_ALIGNMENT`
- `ALIGNMENT`
- `MIXED`
- `MISALIGNMENT`
- `UNKNOWN`

Assessment, confidence (`HIGH`, `MEDIUM`, `LOW`), evidence coverage
(`SUFFICIENT`, `PARTIAL`, `INSUFFICIENT`), and inference category are separate
fields. None is an aggregate score, ranking, competitiveness estimate,
admission probability, or recommendation.

The frozen combination semantics are categorical:

- `MIXED` requires material supporting and contradicting signals;
- `ALIGNMENT` requires material support and no material contradiction;
- `MISALIGNMENT` requires a method-valid material contradiction;
- ordinary material support plus contradiction yields `MIXED`;
- a directly comparable deterministic contradiction of a student-authorized
  `REQUIRED` intent takes precedence and forces `MISALIGNMENT` in its owning
  dimension;
- unknown or incomparable facts never become contradictions;
- `STRONG_ALIGNMENT` requires explicit method permission, a qualifying
  authoritative non-model signal tied to `REQUIRED` or
  `STRONGLY_PREFERRED` intent, and no material contradiction;
- `INSUFFICIENT` coverage permits only `UNKNOWN`;
- model-only directional evidence cannot receive `HIGH` confidence;
- `UNKNOWN` requires a normalized limiting reason with exact provenance.

Under the frozen registry, only the Academic v0.1 method permits
`STRONG_ALIGNMENT`. A future change to another method's permission requires a
new versioned definition and cannot be introduced in application code.

## 4. Authority, provenance, replay, and privacy

Only inputs allowed by the pinned verified method may enter its manifest.
Program fields and student fields use hard allowlists. Only active `VERIFIED`
mappings are authoritative; mapping confidence does not grant authority.
Material directional signals require exact manifested student intent and
authoritative evidence owned by the same method.

Equivalent exact inputs are canonically ordered before hashing. A completed
evaluation records:

- the candidate input fingerprint produced at input sealing;
- the recomputed decision input fingerprint accepted at finalization; and
- the result fingerprint over categorical results, signals, evidence links,
  and structured reasons.

Changing exact evidence, a mapping decision, method, availability state, or
other fingerprint member changes replay identity. Later canonical context
selection does not rewrite a historical pinned selection.

Replay exists only while student-owned data exists. Controlled privacy deletion
removes Fit intents, private access context, manifests, evaluations, results,
signals, reasons, and assembly authorization. It intentionally ends replay and
leaves only the existing non-PII deletion tombstone. Public catalog and
contextual history remain durable.

## 5. SQL finalization boundary

The database is the final integrity authority. The evaluator may assemble a
`BUILDING` evaluation only for its exact verified build authorization. It must
then call `seal_fit_evaluation_inputs(evaluation_id)`, after which assembly
authorization is removed and the candidate input fingerprint is fixed.

`finalize_fit_evaluation(evaluation_id)` is the only completion boundary. It
revalidates all six results, method and policy ownership, source authority,
typed manifest shape, exact evidence, reason compatibility, categorical
combination semantics, confidence and coverage constraints, financial
comparability, international applicability, and the sealed fingerprint before
moving the evaluation to `COMPLETED`.

Authenticated students cannot start or finalize evaluations or fabricate
outputs. Production engine code must not reproduce, bypass, weaken, or replace
the SQL finalizer.

## 6. Verification record

The established final verification results are:

- clean migrations `001`–`011` from an empty database: **PASS**;
- Phase 1 regression suite: **35 assertions PASS**;
- Phase 2 SQL suite: **32 assertions PASS**;
- Phase 3 SQL suite: **98 assertions PASS**;
- eligibility engine: **8/8 PASS**;
- final post-build re-audit: **PASS**;
- migrations `001`–`008`: **unchanged**.

The Phase 3 suite covers schema shape, registry and mapping authority, intent
freezing, exact manifests, field and source allowlists, six-result
completeness, categorical semantics, required-constraint precedence,
confidence and coverage, deterministic financial comparison, international
applicability, fingerprint determinism, mutation resistance, RLS, cross-user
attacks, and privacy deletion.

### PostgreSQL 15 and Supabase auth-stub limitation

The clean rebuild and SQL assertion counts above were verified on PostgreSQL
15 with the repository's Supabase-compatible authentication roles/claims
stubbed for database testing. This validates PostgreSQL schema behavior,
functions, constraints, RLS predicates, and claim-based ownership under that
stub. It is not evidence that the full Supabase local stack, hosted Supabase
Auth lifecycle, JWT issuance/refresh, gateway behavior, or service-role
integration has been exercised end to end.

Before a production evaluator is approved, the same migrations and
cross-user/RLS scenarios must also pass against the real target Supabase stack.
This limitation does not invalidate the frozen SQL contract, but it is an
explicit integration blocker for a production release claim.

## 7. Post-freeze change policy

The following may proceed without a new database-contract version only when
they do not alter persisted meaning or enforcement:

- documentation clarification;
- additive tests;
- query or index optimization with unchanged observable behavior;
- implementation work in a persistence-neutral Fit engine;
- adapters that obey the exact existing SQL boundary.

The following require an additive migration and a new applicable contract,
method, reason, normalization, input-schema, or evaluator-build version:

- changing any dimension, assessment, confidence, coverage, importance, reason,
  source-class, manifest, or inference meaning;
- changing method source classes, field allowlists, required inputs,
  materiality, combination, strong-alignment, or mapping authority;
- changing intent typing, hard-constraint authority, or conflict behavior;
- changing contextual-claim value contracts, authority, applicability,
  selection, or mapping lifecycle;
- changing exact manifest membership, canonical ordering, or fingerprint
  construction;
- changing finalizer checks, completion immutability, RLS, ownership, privacy
  deletion, or replay behavior;
- adding aggregate scoring, ranking, competitiveness, admission probability, or
  recommendation behavior.

Verified definitions, frozen intents, and completed evaluations must never be
rewritten. Supersede or retire through the controlled lifecycle and preserve
historical interpretation.

## 8. Freeze boundary and next milestone

This freeze authorizes design and implementation review for a pure,
deterministic, persistence-neutral Fit engine that conforms to
[`PHASE_3_FIT_ENGINE_PLAN.md`](PHASE_3_FIT_ENGINE_PLAN.md). It does not itself
authorize a production deployment or a semantic expansion.

**Phase 3 overall is NOT frozen. No final Phase 3 tag exists or should be
created yet.** The next gate is Fit engine implementation review, followed by
implementation, cross-layer verification, real Supabase integration
verification, evaluator-build registration, and a separate final Phase 3
freeze decision.