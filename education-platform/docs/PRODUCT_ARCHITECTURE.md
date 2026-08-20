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

The current implementation intentionally covers only the database foundation,
NYU MSQE golden record, provenance, versioning, and tests. The principles below
define migration direction without authorizing speculative tables or services.

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

## 9. Uncertainty is first-class

Recommendations must eventually report more than a score. Outputs should
support:

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

The current milestone remains:

- database foundation
- NYU MSQE golden record
- provenance
- versioning
- tests

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
