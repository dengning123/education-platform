# Product Architecture

## Purpose

This document is the long-term product and engineering source of truth for the
education platform. The product thesis is **Evidence-Based Graduate Education
Decision Intelligence** for students with Chinese undergraduate or university
backgrounds who are considering United States graduate programs.

The product helps a student answer:

- which programs are realistic under explicit published requirements;
- how each program fits academic, career, financial, international,
  geographic, delivery, and personal constraints;
- why a conclusion was reached and which evidence supports it;
- what is missing, stale, conflicting, or uncertain;
- how programs differ on decision-relevant tradeoffs; and
- which programs the student chooses to keep in a defensible shortlist.

It is not a generic AI chatbot, an education-agency workflow clone, a ranking
site, or an unsupported admission-probability generator. Recommendation means
evidence-backed decision support for one student's stated constraints; it does
not mean a global program ranking.

Product development follows this evidence order:

```text
Market evidence
→ capability priority (WHAT)
→ representative student and program evidence
→ minimal semantic contract (HOW)
→ implementation
→ executable validation (CORRECTNESS)
```

The intended decision lifecycle is:

```text
Student evidence and versioned Profile
→ source-backed, versioned Program Data
→ explicit Requirement and Eligibility evaluation
→ multidimensional categorical Fit with uncertainty
→ evidence-backed program Comparison
→ student-controlled Shortlist
→ explained education decision

Later lifecycle extension:
Application → Outcome → separately governed future model research
```

Competitiveness is not a mandatory stage between Fit and a useful decision.
It remains a separate, deferred capability that can be considered only after
sufficient version-pinned applications and verified outcomes exist.

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

International Accessibility is also an independently visible, high-priority
decision domain while remaining one of Fit's categorical dimensions. Future
product evidence may cover international applicant eligibility, SEVP/F-1
context, exact program STEM/CIP status, OPT/STEM OPT context, and current
program-specific international requirements. Every such claim must be
source-backed, applicability-scoped, timestamped, freshness-aware, and able to
remain `UNKNOWN`. This direction does not authorize a generalized Visa Engine
or legal advice.

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

Decision support must not optimize university ranking alone. A student-facing
comparison may include:

- academic fit
- career alignment
- cost
- explicit Eligibility and uncertainty
- location
- international employment accessibility
- student preferences
- expected outcomes

Prestige can be one bounded contextual input when justified, but it is not the
product objective. No global weighted score is authorized by this list.

## 15. Market-evidence capability roadmap

The auditable priority matrix, source registry, real-data audit design, and
foundation-entry rule are maintained in
[`MARKET_EVIDENCE_PRODUCT_CAPABILITY_MATRIX.md`](MARKET_EVIDENCE_PRODUCT_CAPABILITY_MATRIX.md).
Those priority labels guide planning only and do not authorize implementation.

### 15.1 NOW — complete the trustworthy decision foundation

- Profile and representative Chinese-background data handling;
- Program Data and exact version/source freshness;
- Eligibility and prerequisite equivalency;
- Academic and Career Alignment;
- Financial decision foundations;
- International Accessibility as an independently visible decision domain
  while preserving its Fit semantics;
- geographic, delivery/duration, and personal preferences;
- evidence/provenance, confidence/uncertainty, and explanation.

Eligibility remains rule logic. Fit remains categorical preference and
constraint semantics. Competitiveness and Admission Probability remain
separate and unimplemented. Recommendation remains decision support rather
than ranking.

### 15.2 NEXT — turn trusted domain results into a decision product

After the executable Profile → Eligibility → Fit loop and representative
program data are validated, prioritize:

- Program Discovery;
- side-by-side Comparison;
- student-controlled Shortlist;
- Career Outcomes and career-path evidence;
- ROI/value presentation without a composite score;
- tuition, total academic cost, scholarship/funding, and assistantship depth;
- STEM/OPT and source-fresh international-policy context; and
- curriculum comparison.

Comparison must preserve domain conclusions, evidence, reasons, unknowns, and
uncertainty. It must not collapse them into a universal weight, ranking, or
admission probability. Shortlist is a student-owned saved decision set, not a
Reach/Target/Safety classifier, ML ranking, or portfolio optimizer.

Career/ROI work must use source-scoped career pathways, occupations,
employment and salary evidence, internships, employers, and international
constraints. ROI/value presentation may bring together cost, duration,
funding, career evidence, and uncertainty, but this roadmap does not define or
authorize an ROI formula. Financial expansion may cover tuition, fees, billing
basis, duration, total academic cost, scholarships/funding, assistantships,
living-cost context, and normalization uncertainty; it must not collapse them
into one affordability score.

### 15.3 LATER and DEFERRED

Application tracking, offer comparison, advanced location/lifestyle context,
bounded reputation context, and advanced scholarship workflows are later
lifecycle capabilities. The planning-only Application/Outcome contract
remains strategically important for trustworthy outcome collection even
though application tracking is not the next product increment.

Competitiveness, Reach/Target/Safety labels, portfolio optimization, admission
probability, and learned ranking are deferred until the platform has enough
quality-controlled profile snapshots, program snapshots, applications, and
verified outcomes to support bias review, uncertainty, calibration, and
program/cycle effects.

### 15.4 Real-data before new abstraction

The first audit covers 10–20 representative United States graduate programs
across Computer Science/Data/Statistics, Engineering, Business/Analytics, and
Economics/quantitative programs, followed by 50–100 only after Stage 1 gaps are
understood. Each required fact is classified `SUPPORTED`, `PARTIAL`,
`UNKNOWN`, or `UNREPRESENTABLE`.

New schema, migration, RPC, engine, or generalized foundation work enters the
roadmap only when it serves a high-priority market decision demonstrated by
real data, unblocks an executable path, closes a confirmed
correctness/security/privacy defect, or represents a repeated real-data gap.
AI may assist extraction or propose candidate observations; it may not create
authoritative student or program facts without evidence and validation or
review.

## 16. Current MVP scope

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

The forward product milestone remains the Phase 4 minimum authenticated loop;
see
[`PHASE_4_PRODUCTION_OBSERVABILITY_AND_MVP_PLAN.md`](PHASE_4_PRODUCTION_OBSERVABILITY_AND_MVP_PLAN.md).
The separately bounded provisional Migration 031 Application/Outcome proposal is recorded
in
[`MIGRATION_031_APPLICATION_OUTCOME_CONTRACT_PLAN.md`](MIGRATION_031_APPLICATION_OUTCOME_CONTRACT_PLAN.md).
Its migration number remains provisional until implementation authorization.
No Migration 031 Application/Outcome SQL or Competitiveness implementation
exists. Migration 028 is limited to the separately versioned product-aware Fit
input/manifest compatibility build registration, and Migration 029 only makes
the M027 product guard compatible with the existing transaction-bound privacy
deletion lifecycle. Neither changes Fit v0.1 semantic law. Migration 021
is limited to hosted Auth subject compatibility, Migration 022 is limited to
the owner-scoped Profile taxonomy label projection, and Migration 023 is
limited to bounded ASSESSMENT/SKILL taxonomy options. Migration 024's current
bounded Assessment/Skill admissibility work must close its own contract and
baseline before product work proceeds. None authorizes Application/Outcome or
Competitiveness behavior.

Migration 023 does not authorize a Tests/Skills editor. Assessment-specific
section semantics, VERIFIED-active mutation admissibility, historical
ASSESSMENT/SKILL projection, and taxonomy coverage remain UI blockers that
must be closed by database contracts; frontend filtering is not an authority
substitute.

After Migration 024 contract closure and baseline, the forward sequence is:

```text
complete the Profile executable flow
→ run real Profile → Eligibility → Fit end to end
→ validate representative real Program Data
→ implement evidence-preserving Comparison
→ implement student-controlled Shortlist
→ add Career Outcomes / ROI decision support
→ deepen Financial evidence
→ deepen STEM / OPT / International Accessibility evidence
```

Tests/Skills UI resumes only when a real product line requires it. Tests remain
blocked until at least one real assessment has official evidence, a reviewed
definition, VERIFIED status, and executable validation. Skills remain
deferred; labels such as Python, R, and SQL are insufficient evidence for a
general skills taxonomy or editor.

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
