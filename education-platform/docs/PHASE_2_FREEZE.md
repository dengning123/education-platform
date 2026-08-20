# Phase 2 Student Eligibility — FROZEN v0.1

Status: **FROZEN**  
Version: **v0.1**  
Phase: **Phase 2 — Student Eligibility**  
Next phase: **Phase 3 — Fit**  
Freeze date: **2026-08-20**  
Purpose: Preserve the verified eligibility semantics, schema contracts,
evidence requirements, authority boundaries, privacy lifecycle, and
replayability guarantees established during Phase 2.

This record freezes the Phase 2 Student Eligibility architecture and behavior
at v0.1. Phase 1 migrations `001`–`003` remain unchanged and authoritative.
Future Fit work must be implemented as a separate product layer; it must not
expand or reinterpret Eligibility v0.1.

Eligibility asks whether the available accepted evidence defensibly shows that
a student satisfies, does not satisfy, or may satisfy explicitly represented
program requirements. Fit asks how appropriate, attractive, competitive, or
strategically suitable a program is for that student. Phase 2 is not a general
admissions recommendation engine.

## 1. Implemented scope

Phase 2 v0.1 implements:

- a minimal, version-aware taxonomy with stable canonical keys and aliases;
- reviewed mappings from Phase 1 catalog records to taxonomy concepts;
- an anonymous student analytical identity separated from account identity;
- frozen student profile versions containing raw education, course, test,
  experience, skill, preference, and goal facts;
- private student evidence and reviewed student-to-concept mappings;
- completeness scoped by profile version, education context, and data domain;
- append-only, reproducible student derived-feature storage that is explicitly
  excluded from Eligibility v0.1 inputs;
- versioned program requirement trees over accepted Phase 1 observations and
  reviewed mappings;
- controlled database verification and retirement of rule sets;
- a pure, deterministic TypeScript eligibility evaluator;
- normalized evaluation manifests, canonical fingerprints, rule-node results,
  and typed course/test match traces;
- strict RLS, cross-student ownership constraints, and privacy deletion.

## 2. Explicitly excluded scope

The following are not part of Eligibility v0.1:

- admission probability or acceptance-rate prediction;
- competitiveness or subjective profile-strength scoring;
- Reach/Target/Safer classification;
- school or program ranking;
- recommendation ranking or strategic school-list construction;
- preference, financial, location, cultural, or social Fit;
- career-outcome matching;
- essay, recommendation-letter, or extracurricular-strength scoring;
- application-portfolio optimization;
- generic capability scores as substitutes for explicit requirements;
- minimum-score and minimum-grade comparators;
- fuzzy or model-confidence-based equivalency decisions;
- arbitrary activation conditions, waivers, or a generic comparison/EAV rule;
- inferred eligibility based on unsupported assumptions;
- additional university ingestion;
- API, service, frontend, or workflow UI layers.

Fit is the next separate phase. It may consume eligibility outputs, but it must
not change the meaning of Eligibility v0.1 statuses.

## 3. Frozen migrations

- `202608200004_taxonomy_v01.sql`
  - taxonomy releases, stable concepts, aliases, relationships, reviewed
    catalog mappings, mapping history, and taxonomy identity guards.
- `202608200005_student_profiles.sql`
  - private identity boundary, student profile versions, context-scoped
    completeness, private evidence, raw facts, reviewed mappings, RLS, frozen
    snapshot guards, and privacy deletion tombstones.
- `202608200006_student_derived_features.sql`
  - versioned feature definitions and append-only values; these values are not
    eligibility inputs.
- `202608200007_requirement_rules.sql`
  - versioned rule sets, normalized rule trees, source/mapping references,
    verification invariants, retirement, immutability, and audit.
- `202608200008_eligibility_persistence.sql`
  - exact normalized manifests, typed match traces, canonical fingerprints,
    controlled finalization, append-only results, and privacy-aware deletion.

These migrations are now historical artifacts. They must not be edited,
reordered, or squashed after the freeze.

## 4. Eligibility semantics

Eligibility leaves emit only:

- `SATISFIED`
- `NOT_SATISFIED`
- `UNKNOWN`

Eligibility v0.1 never emits `NOT_APPLICABLE`.

Group propagation is fixed:

- `ANY`: any satisfied child yields `SATISFIED`; otherwise any unknown child
  yields `UNKNOWN`; otherwise `NOT_SATISFIED`.
- `ALL`: any not-satisfied child yields `NOT_SATISFIED`; otherwise any unknown
  child yields `UNKNOWN`; otherwise `SATISFIED`.
- `AT_LEAST(k)`: with `s` satisfied and `u` unknown children, return
  `SATISFIED` when `s >= k`, `NOT_SATISFIED` when `s + u < k`, and `UNKNOWN`
  otherwise.

Overall statuses are:

- `ELIGIBLE`: every ordinary hard requirement is satisfied and no unresolved
  applicable conditional hard requirement remains.
- `NOT_ELIGIBLE`: an ordinary hard path is conclusively not satisfied.
- `UNKNOWN`: missing or conflicting program facts, incomplete student data,
  unsupported semantics, or unresolved mapping authority prevents a
  deterministic conclusion.
- `CONDITIONALLY_ELIGIBLE`: all ordinary hard requirements are satisfied and a
  verified, officially stated conditional/remediable hard requirement is known
  to apply.

Soft requirements are explanatory and non-blocking. Evidence coverage and
mapping confidence never determine eligibility.

## 5. Student completeness and evaluation manifests

`student_data_completeness` is scoped by:

- exact frozen `profile_version_id`;
- optional `education_context_id`;
- controlled data domain;
- `COMPLETE`, `PARTIAL`, or `UNKNOWN`.

`COURSE_HISTORY` and `COURSE_MAPPING` coverage is required independently for
every declared education context. Completeness for an exchange semester cannot
establish completeness for another institution. Absence becomes
`NOT_SATISFIED` only when every relevant context has complete raw-history and
mapping coverage; otherwise it remains `UNKNOWN`.

Each evaluation pins exact relational manifest rows for:

- degrees, courses, and test scores;
- student mappings and student evidence;
- completeness records with their education context and domain;
- accepted catalog observations;
- reviewed catalog mappings;
- taxonomy concepts;
- profile, rule-set, taxonomy, evaluator, and input-contract versions.

Fingerprint construction sorts every manifest association before hashing.
Equivalent insertion order produces the same fingerprint. Replacing an exact
course or mapping ID produces a different fingerprint even when the replacement
resolves to the same concept.

## 6. Mapping verification authority

Only an active `VERIFIED` mapping is normative. Database constraints require:

- a reviewer identity;
- a review timestamp;
- verification evidence;
- a model version when the proposal method is `MODEL`.

`confidence` is proposal metadata only. A high-confidence model proposal cannot
satisfy a requirement without the same review authority and evidence required
for other methods.

Verified catalog mappings cannot be downgraded or overwritten; they may only be
retired. Rejected and retired mappings are immutable. Student mappings are also
immutable once their profile version is frozen.

Rule-set verification rejects disconnected or cyclic trees, cross-rule-set
parents, invalid group cardinality, unsupported predicates, sources outside the
target program version, non-current canonical observations, and non-verified or
retired mappings.

If a mapping referenced by a historical verified rule set is later retired:

- the verified historical tree is not rewritten;
- existing completed evaluations remain intact;
- the old rule set cannot be used for a new evaluation;
- a new reviewed mapping and a new verified rule-set version are required.

## 7. Privacy and replayability contract

Catalog provenance prioritizes durable history. Student data prioritizes
privacy-compliant deletion.

Evaluations are replayable only while their student-owned inputs exist.
Controlled student deletion removes:

- account identity links;
- raw student records and evidence;
- student mappings and derived values;
- manifests, match traces, and eligibility evaluations.

Deletion leaves only a non-PII tombstone containing deletion time and reason.
It retains no student identifier or document hash. Privacy deletion
intentionally ends full replayability; it does not delete Phase 1 catalog
history.

### 7.1 Historical integrity

Canonical program changes do not destroy historical evaluation state.
Retirement and versioning must be used instead of destructive mutation where
the frozen schema provides them. Historical rule sets, mapping decisions, and
completed evaluations remain interpretable under the contract that produced
them, subject only to the intentional student privacy-deletion lifecycle.
Historical constraints must not be weakened merely to simplify later writes.

## 8. NYU MSQE rule-set status

NYU MSQE has no production `VERIFIED` eligibility rule set in v0.1. Its
eligibility interpretation remains draft/unseeded because current Phase 1
evidence does not support every required leaf and mapping at the verification
standard.

Synthetic rule sets exist only inside rolled-back test fixtures. No rule was
weakened or promoted merely to produce a real-program `ELIGIBLE` demo.

## 9. `EXPLICIT_CONDITIONAL` governance

`EXPLICIT_CONDITIONAL` is allowed only when official evidence clearly states a
conditional or remediable admission path, such as completion of a named
requirement before enrollment.

It still requires human evidence review. Ambiguous statements such as
"students without sufficient background may..." must not be encoded directly
as conditional eligibility without an approved interpretation. The database
can enforce evidence presence and review authority, but it cannot determine
whether source language is semantically explicit enough.

## 10. Final test matrix

Final clean PostgreSQL 15 rebuild on 2026-08-20:

- migrations `001`–`008` from an empty database: **PASS**
- unchanged Phase 1 regression suite: **PASS**
- Phase 2 SQL assertions: **PASS**
- TypeScript strict typecheck: **PASS**
- exhaustive `ANY`, `ALL`, and `AT_LEAST(k)` truth tables: **PASS**
- nested `UNKNOWN` / `NOT_SATISFIED` propagation: **PASS**
- deterministic deep-equality and input-mutation checks: **PASS**
- education-context completeness isolation: **PASS**
- mapping reviewer/timestamp/evidence constraints: **PASS**
- model-confidence non-authority: **PASS**
- cross-rule-set and cross-program source attacks: **PASS**
- retired-mapping verification and evaluation attacks: **PASS**
- canonical fingerprint ordering and exact-mapping sensitivity: **PASS**
- RLS owner and unrelated-user default-deny checks: **PASS**
- cross-student ownership attacks: **PASS**
- privacy deletion and non-PII tombstone checks: **PASS**

TypeScript evaluator result: 8 tests passed, 0 failed.

## 11. Post-freeze change policy

Implementation-preserving work does not require a new semantic version when it
does not alter externally observable eligibility meaning. Examples include:

- performance or query optimization;
- additional tests;
- documentation clarification;
- internal refactoring;
- logging or observability improvements;
- bug fixes that restore behavior already specified by this record.

After this freeze, the following require a new additive SQL migration and,
where semantics change, a new rule-schema or engine-contract version:

- adding or changing a predicate kind;
- changing three-valued group propagation or overall status semantics;
- adding activation conditions, waivers, score/grade comparisons, or another
  leaf state;
- changing completeness domains, education-context scope, or absence rules;
- changing mapping authority or verification requirements;
- changing manifest membership, canonical ordering, or fingerprint inputs;
- changing rule-set verification or retirement behavior;
- changing privacy deletion, replayability, RLS, or ownership guarantees;
- changing taxonomy concept identity semantics.

Verified rule sets and completed evaluations must never be rewritten. Create a
new rule-set version, retire obsolete mappings or interpretations, and preserve
historical results.

Display labels, documentation clarifications, and additive tests may change
without a semantic version only when they do not alter persisted meaning,
evaluation behavior, fingerprint construction, authority, or privacy
contracts.

## 12. Phase boundary: Eligibility to Fit

Fit may consume Eligibility outputs, but it must not mutate their meaning:

```text
Program Sources
  → Canonical Program Data
  → Eligibility Rules
  → Student Evidence + Manifest
  → Verified Mappings
  → Eligibility Evaluation
  ─────────────────────────────
       FROZEN PHASE BOUNDARY
  ─────────────────────────────
  → Fit
  → Ranking / Recommendation / Strategy
```

Eligibility remains the stable factual and evidentiary substrate. Fit may
reason over that substrate but must not rewrite it.

Phase 2 Student Eligibility is formally **FROZEN v0.1**.

Next development phase: **Phase 3 — Fit**.
