# Product Architecture

## Purpose

This document is the long-term product and engineering source of truth for the
education platform. The product is not merely a university and program
catalog. It is an evidence-backed education and career decision platform for
international students.

The intended decision lifecycle is:

```text
Student Raw Data
→ Student Features
→ Career / Education Path Exploration
→ Requirement & Eligibility Engine
→ Program Fit
→ Competitiveness
→ Uncertainty / Confidence
→ Recommendation
→ Application
→ Outcome
→ Future Model Improvement
```

The current implementation covers the frozen Phase 1 database foundation, the
frozen Phase 2 Student Eligibility v0.1 contract, the Phase 3 Fit v0.1
database/persistence layer frozen separately in migrations `009`–`011`
([`PHASE_3_DATABASE_FREEZE.md`](PHASE_3_DATABASE_FREEZE.md)), and Migration
`012` Foundation Hardening / Gate 1
([`PHASE_1_2_FOUNDATION_HARDENING_FREEZE.md`](PHASE_1_2_FOUNDATION_HARDENING_FREEZE.md)),
and Migration `013` Eligibility Correctness v0.2
([`PHASE_2_ELIGIBILITY_V02_FREEZE.md`](PHASE_2_ELIGIBILITY_V02_FREEZE.md)).
Migrations `014` and `015` are separately frozen by their Phase 3 hardening
records. The authorized engine implementation contract is
[`PHASE_3_FIT_ENGINE_PLAN.md`](PHASE_3_FIT_ENGINE_PLAN.md).
Phase 3 Fit v0.1 is frozen by
[`PHASE_3_FREEZE.md`](PHASE_3_FREEZE.md). The production release contains the
Fit Engine v0.1 TypeScript evaluator, controlled persistence adapter,
registered evaluator build, authenticated Edge APIs, and independently
reviewed Financial normalization workflow. Migrations `001`–`018` and all four
Edge Functions are remotely deployed and behavior-verified. Scores, weights,
rankings, recommendations, Competitiveness, and Admission Probability remain
outside the Fit contract and are not implemented.

## 1. Raw data and derived data

Model inference is never source data.

Program raw facts include official curriculum, requirements, costs, deadlines,
policies, and outcomes. Program-derived features may include quantitative
intensity, research intensity, finance relevance, and career alignment.

Student raw data includes courses, grades, experiences, skills, preferences,
and goals. Student-derived features may include quantitative strength,
research strength, finance exposure, and career readiness.

Raw and derived data must remain structurally separate. Derived values must
identify their model or rule version, calculation time, and inputs or input
snapshot. An estimate must never silently populate an official-fact column.

## 2. Program identity and program version

A program is a persistent entity. Admissions requirements, curriculum,
tuition, deadlines, STEM status, and other time-sensitive facts belong to a
program version.

Historical applications and outcomes must remain linked to the exact program
version that existed when the student applied. A newer source or admissions
cycle creates or updates the appropriate version; it does not rewrite history.

Admissions cycle, academic year, entry term, deadline date, and source-validity
dates represent different concepts and must remain separate.

## 3. Evidence-backed facts

Application-facing canonical facts must be supported by evidence. Provenance
must retain:

- source and publisher
- URL
- retrieval and verification dates
- verification status
- applicability
- granularity
- population scope

Official does not mean directly applicable. IPEDS undergraduate admissions
statistics, for example, must not be interpreted as NYU MSQE admissions
statistics. Evidence describes what a source claims; canonical selection
records whether that claim is currently accepted for an exact field and
context.

## 4. Unknown is a valid state

Missing program data must never be guessed. Supported states include:

- `KNOWN`
- `NOT_YET_VERIFIED`
- `NOT_PUBLICLY_DISCLOSED`
- `NOT_APPLICABLE`
- `SOURCE_CONFLICT`
- `STALE`

Additional workflow states may distinguish unresearched from researched but
unverified data. Unknown typed facts remain `NULL`. Missing, stale, sparse, or
conflicting evidence reduces confidence instead of producing fabricated
values.

## 5. Taxonomy is required for comparability

Official names must be preserved exactly. Matching and comparison must
eventually use standardized internal taxonomy for programs, fields, subfields,
courses, skills, careers, and industries rather than free-text equality.

Financial Engineering, Quantitative Finance, Mathematical Finance, and
Financial Economics remain distinct official concepts while also mapping to
standardized concepts and relationships. Taxonomy mappings must be versionable
and auditable because classification systems evolve.

## 6. Career, major, and program relationships are many-to-many

Career-to-major-to-program is not a linear pipeline. One career can have
multiple viable educational paths, and one program can support multiple
careers.

Future architecture must support many-to-many relationships among students,
skills, careers, fields, programs, industries, and outcomes. No component may
hard-code one career to one major or program.

## 7. Requirement engine before fit engine

Explicit requirements and preferences are evaluated before recommendation
scoring. Requirements may contain:

- `AND` and `OR` logic
- alternatives and waivers
- minimum grades
- required and recommended courses
- preferred backgrounds
- conditional requirements

The engine must distinguish hard constraints, soft preferences, background
gaps, and remediable gaps. A future result may state:

```text
Eligibility: ELIGIBLE
Gap: Linear Algebra
Severity: Moderate
Suggested action: Take Linear Algebra before application
```

Prerequisite logic must not be reduced to independent boolean columns.

## 8. Eligibility, fit, and competitiveness are distinct

Eligibility asks whether explicit requirements are satisfied.

Fit asks how well a program serves the student's academic, career, financial,
geographic, and personal goals.

Competitiveness compares the applicant with the likely applicant pool, subject
to available evidence.

Fit is not an admission probability. Admission probabilities must not be
implemented without sufficient validated outcomes and an appropriate
statistical methodology.

### Future Competitiveness modeling direction (not authorized)

A future, separately approved Competitiveness or admission-outcome phase may
estimate feature effects from historical application snapshots and verified
outcomes. This statistical learning belongs only to Competitiveness: it must
not replace Eligibility's explicit rule logic or Fit's categorical
preference-and-constraint semantics.

Any learned effects or weights are versioned model outputs, not fixed student
attributes or canonical source facts. The model must retain the exact model
version and input snapshot used for each result and should account for
uncertainty, calibration, program effects, admissions-cycle effects, and
relevant interactions or nonlinearities. When outcome data for an individual
program is sparse, the preferred direction is a hierarchical or
partial-pooling approach that can borrow appropriately scoped information
from related program families while allowing program-specific evidence to
dominate as it grows.

Historical outcomes are therefore candidates for future model improvement,
not authorization to assign global manual weights or to produce admission
probabilities now. This note records a research and architecture direction
only. It does not change any frozen Eligibility or Fit semantic contract and
does not authorize a Competitiveness model or Admission Probability and does
not expand the separately authorized categorical Fit Engine scope.

## 9. Uncertainty is first-class

If a later, explicitly versioned phase introduces numerical scores, outputs
must report more than a score and should support:

- score
- confidence
- evidence coverage

For example:

```text
Academic Fit: 88/100
Confidence: HIGH
Evidence Coverage: 91%
```

Confidence and evidence coverage are separate from the score. Sparse, stale,
inapplicable, or conflicting inputs must reduce confidence.

This is not the Phase 3 v0.1 contract. Fit v0.1 uses categorical per-dimension
conclusions with reasons and uncertainty and defines no numerical or composite
Fit Score.

## 10. International-student outcomes are distinct

General career outcomes are not substitutes for international-student career
outcomes. Future analysis may include:

- STEM and CIP classification
- F-1 considerations
- OPT relevance
- English-language policy
- credential evaluation
- international deadlines
- internship timing
- geographic recruiting
- employer sponsorship environment

Career quality and international career accessibility remain separate
dimensions with explicit population and geographic scope.

## 11. Application outcomes require bias awareness

User-submitted admission outcomes are not random samples. Risks include
selection bias, self-reporting bias, year effects, institution-background
effects, geographic concentration, missing data, and small sample sizes.

Outcomes must not automatically become admission probabilities. Any future
competitiveness model must preserve cohort, source, verification status,
population scope, and sample size. Model outputs must disclose methodological
and evidence limitations.

## 12. Data freshness is architectural

High-change fields such as deadlines, test policies, tuition, STEM status, and
application requirements will require source-refresh monitoring.

The architecture must remain compatible with scheduled source checks, content
hashes, change detection, AI-assisted comparison, human or rule verification,
canonical selection, and append-only audit history. A changed webpage creates
a candidate observation; it does not automatically overwrite a canonical
fact.

## 13. Privacy by design

Future student data may contain sensitive educational, identity, and
application information. Authentication and legal identity data must remain
separable from analytical student profiles.

Analytics and model training should use anonymous internal student identifiers
wherever possible. Data ownership, retention, access controls, consent,
deletion, and anonymization must be designed before student data is introduced.
Derived records must remain traceable enough to delete or anonymize outputs
that depend on a student.

## 14. The optimization target is not prestige

The recommendation system must not optimize university ranking alone.
Personalized expected value may include:

- academic fit
- career alignment
- cost
- admission risk
- location
- international employment accessibility
- student preferences
- expected outcomes

Prestige can be one contextual input when justified, but it is not the product
objective.

## 15. Current MVP scope

Completed and frozen:

- Phase 1 database foundation, NYU MSQE golden record, provenance, versioning,
  and regression tests;
- Phase 2 Student Eligibility v0.1, including student evidence, completeness,
  reviewed mappings, verified rule trees, deterministic evaluation, privacy,
  and replay contracts;
- Migration `012` Foundation Hardening / Gate 1, additive over `001`–`011`;
  see [`PHASE_1_2_FOUNDATION_HARDENING_FREEZE.md`](PHASE_1_2_FOUNDATION_HARDENING_FREEZE.md);
- Migration `013` Eligibility Correctness v0.2, additive over frozen `012`;
  see [`PHASE_2_ELIGIBILITY_V02_FREEZE.md`](PHASE_2_ELIGIBILITY_V02_FREEZE.md).
- Migration `014` Financial Billing Basis Hardening and Migration `015` Fit
  Replay and Seal Hardening, each under its independent freeze record.

Current approved semantic contract:

- Phase 3 Fit product semantics and boundaries;
- multidimensional categorical conclusions, evidence-backed reasons, and
  separate confidence and categorical evidence coverage;
- no composite Fit Score, ranking, competitiveness, or probability.

Current implementation milestone: the Phase 3 Fit v0.1 database contract is
frozen in migrations `009`–`011` and SQL tests. Migration `012` Foundation
Hardening is **FROZEN**. Migration 013 — Eligibility Correctness v0.2 is
**FROZEN**
([`PHASE_2_ELIGIBILITY_V02_FREEZE.md`](PHASE_2_ELIGIBILITY_V02_FREEZE.md)).
The Fit TypeScript evaluator, controlled adapter, evaluator-build registration,
evaluation Edge API, and separate Financial normalization
prepare/review/resume workflow are locally and remotely verified and frozen by
[`PHASE_3_FREEZE.md`](PHASE_3_FREEZE.md). Financial normalization is limited
to the versioned, independently reviewed same-currency annualization contracts
in Migration `017`; unsupported conversion or review states fail closed.
Ranking, probability, recommendation, and Competitiveness remain unimplemented.

The next planning milestone is Phase 4 production observability and a minimum
authenticated product loop; see
[`PHASE_4_PRODUCTION_OBSERVABILITY_AND_MVP_PLAN.md`](PHASE_4_PRODUCTION_OBSERVABILITY_AND_MVP_PLAN.md).
The separately bounded Migration 019 Application/Outcome proposal is recorded
in
[`MIGRATION_019_APPLICATION_OUTCOME_CONTRACT_PLAN.md`](MIGRATION_019_APPLICATION_OUTCOME_CONTRACT_PLAN.md).
Both are planning-only. No Migration 019 SQL or Competitiveness implementation
exists.

Do not implement the full future architecture now. Add no speculative tables,
services, matching engines, or model pipelines merely because they appear in
this document.

Prefer the smallest implementation that preserves a clean migration path.
Changes should be made now only when they are inexpensive today and would be
materially expensive or dangerous to retrofit after real program, student, or
outcome data exists.

## Current architectural invariants

The MVP establishes the following invariants for future work:

1. Canonical typed columns are application-facing values; observations and
   evidence are immutable provenance and history.
2. A controlled acceptance operation updates canonical value and evidence
   selection atomically.
3. Program identity and cycle-specific facts are separate.
4. Raw facts, derived features, and external contextual metrics are separate.
5. External metrics declare granularity, applicability, population scope, and
   rationale.
6. Audit history is append-only.
7. Unknown facts remain null and carry an explicit knowledge state.
8. New automated ingestion may propose observations but may not automatically
   replace canonical facts.
