# Phase 3 Fit Specification

Status: **SEMANTIC CONTRACT APPROVED — READY FOR DATA MODEL DESIGN**  
Specification version: **v0.1**
Phase: **Phase 3 — Fit**
Upstream contract: **`phase2-eligibility-v0.1`**
Implementation status: **Not started**

## 1. Purpose

Phase 3 defines an evidence-backed, multidimensional, explainable assessment
of how well a program matches a student's stated goals, constraints,
preferences, and relevant background.

A Fit assessment is a relationship between one exact frozen student profile
version and one exact program version. It may consume a pinned Phase 2
eligibility result as adjacent context without reinterpreting that result's
statuses.

The defining question is:

> How well does this program serve this student's stated goals, constraints,
> and preferences, given the available evidence?

Fit v0.1 produces categorical conclusions by dimension, structured reasons,
and explicit uncertainty through separate confidence and evidence-coverage
fields. It does not produce a composite score.

## 2. Frozen upstream boundary

The annotated Git tag `phase2-eligibility-v0.1` is the **immutable upstream
contract** for Fit. Phase 3 may consume Phase 2 records and outputs, but it must
not modify or reinterpret:

- eligibility statuses or three-valued rule semantics;
- student completeness and absence semantics;
- mapping verification authority;
- eligibility manifests or fingerprint construction;
- privacy deletion and replayability behavior;
- migrations `004`–`008`.

If Fit exposes a genuine deficiency in Eligibility, the correction requires a
new additive migration and a new rule-schema/engine-contract version. Fit must
never patch the frozen contract indirectly through application logic.

## 3. Product boundaries

The product concepts remain separate:

- **Eligibility**: Does accepted evidence show that the student satisfies, does
  not satisfy, or may satisfy explicit program requirements?
- **Fit**: How well does the program align with the student's stated goals,
  constraints, preferences, and relevant background?
- **Competitiveness**: How does the applicant compare with the likely applicant
  pool?
- **Admission probability**: What calibrated probability of admission is
  supported by validated outcome data and methodology?
- **Admissions strategy**: How should a student construct and prioritize an
  application portfolio?

**Fit ≠ Eligibility ≠ Competitiveness ≠ Admission Probability ≠
Recommendation Ranking.** Fit is not a proxy for any of those concepts. In
particular:

- high Fit does not imply likely admission;
- low Fit does not mean ineligible;
- eligibility gaps do not automatically reduce Fit;
- missing Fit evidence does not imply weak Fit;
- Fit conclusions must not become Reach/Target/Safer labels;
- Fit v0.1 does not rank programs.

An eligibility result may be displayed alongside Fit, but it is not a Fit
dimension and is not folded into a Fit conclusion.

## 4. Fit v0.1 output contract

Every dimension returns one conclusion:

- `STRONG_ALIGNMENT`
- `ALIGNMENT`
- `MIXED`
- `MISALIGNMENT`
- `UNKNOWN`

These states are directional assessments, not scores:

- `STRONG_ALIGNMENT`: multiple material, well-supported signals align and no
  material contradiction is known.
- `ALIGNMENT`: the known material evidence is directionally aligned, but the
  support is narrower or less complete than `STRONG_ALIGNMENT`.
- `MIXED`: material supporting and contradicting evidence are both present.
- `MISALIGNMENT`: known material evidence conflicts with an explicit student
  goal, constraint, or preference.
- `UNKNOWN`: the available or interpretable evidence cannot defensibly support
  a directional assessment.

`UNKNOWN` is not neutral, average, moderate, or poor Fit. `MIXED` requires real
supporting and contradicting evidence; missing information alone never
produces `MIXED`.

Formally:

```text
UNKNOWN != NEUTRAL != MISALIGNMENT
```

`NEUTRAL` is declared student intent about a preference. `UNKNOWN` is an
assessment state caused by insufficient or unusable evidence.
`MISALIGNMENT` is a directional assessment supported by known contradicting
evidence.

Every result also includes:

- stable reason codes;
- supporting evidence references;
- contradicting evidence references;
- missing or unresolved inputs;
- `confidence`: `LOW`, `MEDIUM`, or `HIGH`;
- `evidence_coverage`: `SUFFICIENT`, `PARTIAL`, or `INSUFFICIENT`;
- `inference_method`: `DETERMINISTIC_COMPARISON`, `RULE`,
  `REVIEWED_MAPPING`, or `MODEL_INFERENCE`;
- inference-method version;
- exact input-manifest reference;
- a short evidence-bounded explanation.

Assessment, confidence, coverage, and method are separate:

- **assessment** records direction;
- **coverage** records how much of the declared dimension input contract is
  known, relevant, and usable;
- **confidence** records how certain the selected method is about its
  conclusion given the evidence actually available;
- **method** records how the conclusion was produced.

Coverage does not mechanically calculate confidence. Each versioned dimension
method declares required versus optional evidence:

- `SUFFICIENT`: the evidence required for the method's conclusion is known,
  applicable, and usable;
- `PARTIAL`: some declared evidence is unavailable, but a bounded conclusion
  may still be supported by decisive applicable evidence;
- `INSUFFICIENT`: evidence for the core dimension question is unavailable or
  unusable and the assessment must normally be `UNKNOWN`.

Missing optional evidence does not automatically prevent an assessment.
Substantial authoritative contradiction may support `MISALIGNMENT` with
`PARTIAL` coverage even when unrelated evidence is missing. If missing
evidence could reasonably reverse the directional conclusion, the assessment
must be `UNKNOWN`.

Fit v0.1 defines no formula such as:

```text
confidence = f(evidence_coverage)
```

Fit v0.1 has:

- no `0–100` dimension scores;
- no weighted aggregate;
- no composite Fit Score;
- no recommendation rank;
- no admission probability.

### 4.1 Constraint and preference importance

Every student-supplied Fit constraint or preference declares one importance:

- `REQUIRED`
- `STRONGLY_PREFERRED`
- `PREFERRED`
- `NEUTRAL`
- `UNSPECIFIED`

`REQUIRED` is a student-defined Fit constraint, not a program admission
requirement. Violating it may produce dimension-level `MISALIGNMENT`, but it
must not change Phase 2 eligibility.

`STRONGLY_PREFERRED` and `PREFERRED` preserve explicit user priority without
assigning hidden numerical weights. `NEUTRAL` records that the student does not
prefer either direction. `UNSPECIFIED` means the system has no preference to
evaluate and must not infer one.

Fit v0.1 does not learn importance, convert importance to weights, or aggregate
importance across dimensions.

### 4.2 Within-dimension combination and precedence

Fit v0.1 uses no numeric aggregation, weighted averaging, majority vote,
percentages, hidden points, or implicit `+1/-1` system.

A versioned dimension method evaluates material signals under its dimension
contract:

- meaningful supporting evidence with no material contradiction may produce
  `ALIGNMENT`;
- evidence satisfying the method's higher strong-alignment bar may produce
  `STRONG_ALIGNMENT`;
- meaningful supporting and meaningful contradicting evidence produce
  `MIXED`;
- a confirmed material contradiction may produce `MISALIGNMENT`;
- insufficient evidence, unresolved applicability, or missing required inputs
  produce `UNKNOWN`.

Missing evidence is never contradicting evidence. Each versioned method defines
and audits what counts as material.

A confirmed contradiction of a comparable student-declared `REQUIRED`
constraint takes precedence and produces `MISALIGNMENT` in the owning
dimension. Other positive signals in that dimension cannot override it. If the
program fact is unknown or incomparable, the result is `UNKNOWN`, not
`MISALIGNMENT`.

Required-constraint precedence:

- does not change Eligibility;
- does not imply low Competitiveness;
- does not create an overall Fit conclusion;
- does not remove a program from a future recommendation list.

`STRONG_ALIGNMENT` has a higher evidence bar than `ALIGNMENT` and is permitted
only when the versioned method explicitly allows it and either:

- multiple material positive signals support the same conclusion with no
  material contradiction; or
- authoritative program evidence strongly satisfies a directly comparable,
  high-importance student goal/preference with no material contradiction.

One weak signal cannot produce `STRONG_ALIGNMENT`. Model inference alone,
prestige, ranking, selectivity, GPA, admission tests, or any prohibited signal
cannot upgrade a dimension to `STRONG_ALIGNMENT`.

## 5. Fit Dimension Contract

The six initial semantic dimensions are **Academic Alignment**, **Career
Alignment**, **Financial Alignment**, **Geographic/Delivery Alignment**,
**Personal Preference Alignment**, and **International Accessibility**. The
short “Fit” headings below are display labels only and do not change these
canonical dimension names.

Every dimension is governed by the same contract fields:

- question answered;
- allowed student inputs;
- allowed program inputs;
- allowed external/reviewed evidence;
- forbidden inputs;
- deterministic comparisons;
- permitted evidence-backed inference;
- conditions producing alignment;
- conditions producing misalignment;
- conditions producing `MIXED`;
- `UNKNOWN` conditions;
- evidence requirements;
- cross-dimension exclusions.

### 5.1 Academic Fit

**Question answered**

> Do the program's curriculum, content, academic orientation, and subject
> emphasis align with what the student explicitly wants to study?

**Allowed student inputs**

- explicit academic interests, course/subject interests, and academic goals;
- relevant student coursework when used as alignment context rather than an
  admission threshold;
- declared preference importance.

**Allowed program inputs**

- canonical curriculum and program-course records;
- evidence-backed program academic characteristics;
- concentrations, academic tracks, thesis/research structure, and required
  academic content.

**Allowed external/reviewed evidence**

- active reviewed course, subject, and field mappings;
- versioned derived signals that remain separate from raw facts.

**Forbidden inputs**

- GPA as a proxy for Fit;
- GRE/GMAT or other admission-test performance;
- whether prerequisites are satisfied;
- eligibility status or requirement-level eligibility failures;
- admission probability or competitiveness;
- school prestige or generic ranking.

**Deterministic comparisons**

- explicit desired subjects versus reviewed curriculum subject mappings;
- explicitly excluded content versus canonical required curriculum;
- required thesis/research/course structure versus verified program structure.

**Permitted evidence-backed inference**

- evidence-backed interpretation of curriculum emphasis;
- academic-direction alignment derived from reviewed mappings and versioned
  methods.

**Conditions producing alignment**

- known material curriculum directly supports explicit academic goals;
- reviewed subject mappings show substantial overlap with strongly preferred
  study areas;
- `STRONG_ALIGNMENT` additionally requires broad, relevant support and no
  known material contradiction.

**Conditions producing `MIXED`**

- meaningful curriculum evidence supports some material academic goals while
  other known curriculum evidence contradicts different material goals;
- supporting and contradicting evidence are both applicable and neither can be
  dismissed as merely missing information.

**`UNKNOWN` conditions**

- academic goals or interests are missing/`UNSPECIFIED`;
- curriculum coverage is insufficient;
- relevant mappings are proposed, rejected, retired, or unresolved;
- available evidence cannot distinguish alignment from misalignment.

**Conditions producing misalignment**

- known material curriculum conflicts with an explicit `REQUIRED` academic
  constraint;
- the program demonstrably lacks a strongly desired academic direction and
  coverage is sufficient to establish that absence.

**Evidence requirements**

- accepted program-version facts;
- explicit student goals/preferences with importance;
- active reviewed mappings;
- method/version and exact evidence references for inference.

**Cross-dimension exclusions**

Academic Fit does not own costs, location, international accessibility,
employment probability, or prerequisite satisfaction.

### 5.2 Career Fit

**Question answered**

> Does the program's curriculum, demonstrated outcomes, recruiting context,
> and career orientation align with the student's target roles, industries,
> and employment geographies?

**Allowed student inputs**

- explicit student career and industry goals;
- target roles, employment geographies, and preference importance;
- relevant stated skill-development goals.

**Allowed program inputs**

- curriculum and experiential-learning opportunities;
- officially stated program career outcomes or program purpose;
- canonical program structure relevant to career preparation.

**Allowed external/reviewed evidence**

- active reviewed program-to-career, skill, and industry mappings;
- outcome evidence with declared population, geography, time period, sample
  size, and applicability;
- external labor-market and employer/recruiting evidence with appropriate
  occupational, geographic, population, and time scope.

Career evidence is classified by authority:

1. officially stated career outcomes or program purpose;
2. reviewed program-to-career mappings;
3. observed historical outcomes with population and applicability metadata;
4. model-generated hypotheses.

The fourth category may propose research or a mapping review. It cannot by
itself support `STRONG_ALIGNMENT` or `HIGH` confidence.

**Forbidden inputs**

- program name or marketing language treated as proof of career outcomes;
- unreviewed curriculum-to-career similarity treated as fact;
- model-generated hypotheses treated as verified mappings;
- applicant competitiveness, salary prediction, or employment probability;
- institution-wide outcomes presented as direct program outcomes.

**Deterministic comparisons**

- explicit target career/industry versus an active reviewed program-to-career
  mapping;
- required experiential format versus a verified program opportunity.

**Permitted evidence-backed inference**

- curriculum/career relevance from reviewed mappings;
- triangulation of official statements, applicable outcomes, and recruiting
  context;
- inference with explicit limitations when outcome evidence is indirect.

**Conditions producing alignment**

- an explicit target role/industry is supported by official outcomes or active
  reviewed mappings plus applicable curriculum/program evidence;
- applicable historical or labor-market evidence corroborates rather than
  substitutes for the program evidence;
- `STRONG_ALIGNMENT` requires multiple authoritative, applicable signals and
  no material contradiction.

**Conditions producing `MIXED`**

- reviewed curriculum/mapping evidence supports the target path while
  applicable historical or labor-market evidence materially contradicts it;
- distinct explicit career goals receive meaningful supporting and
  contradicting evidence.

**`UNKNOWN` conditions**

- student career goals are missing/`UNSPECIFIED`;
- only a program title or model hypothesis links the program to the career;
- historical outcomes lack program, population, geographic, or time
  applicability;
- evidence is too sparse or conflicting for a directional conclusion.

**Conditions producing misalignment**

- sufficiently covered, reviewed evidence materially contradicts an explicit
  target role, industry, or career geography;
- a `REQUIRED` career-path feature is known not to exist.

**Evidence requirements**

- evidence category and authority;
- source population, geography, period, and sample size for observed outcomes;
- reviewed mapping IDs and taxonomy version;
- inference method/version and supporting/contradicting evidence.

**Cross-dimension exclusions**

Career Fit does not own admission likelihood, applicant competitiveness,
international work authorization, affordability, or geographic preference.

### 5.3 Financial Fit

**Question answered**

> Do known costs, funding information, and financial commitments align with
> the student's explicit budget, funding constraints, and cost preferences?

**Allowed student inputs**

- explicit student budget, budget basis, funding facts, and preference
  importance;
- explicit scholarship assumptions only when declared as assumptions rather
  than facts;
- timing/cash-flow constraints.

**Allowed program inputs**

- canonical tuition, mandatory fees, billing basis, and program duration;
- verified scholarship or assistantship information;
- program/location-specific living-cost estimates with applicability metadata.

**Allowed external/reviewed evidence**

- pinned currency conversion where required;
- applicable external living-cost evidence;
- reviewed cost estimates that preserve components, period, and estimation
  method;
- explicit completeness for tuition, mandatory fees, living costs, funding,
  and aid.

**Forbidden inputs**

- tuition alone treated as total cost;
- unlike cost/budget bases compared without normalization;
- unknown scholarship or family funding assumed to be zero or available;
- prestige, admission probability, or speculative return on investment;
- model-estimated affordability presented as a student fact.

**Deterministic comparisons**

- comparable known total cost versus a student budget with the same currency,
  time period, included components, and net/gross basis;
- known mandatory deposit or payment constraint versus an explicit
  `REQUIRED` cash-flow constraint.

If currency, inflation, period, or cost-scope normalization is required, the
comparison must pin an approved versioned normalization method. Without one,
the assessment is `UNKNOWN`.

Fit must not invent exchange rates, living costs, scholarship amounts, family
contribution, future income, or financial aid. Future normalization methods may
be added without changing these v0.1 semantics.

**Permitted evidence-backed inference**

- `known mismatch`: comparable sufficiently complete cost exceeds a compatible
  explicit budget;
- `potential mismatch`: known components already approach/exceed budget while
  material costs or funding remain unknown;
- `unknown affordability`: cost, budget basis, aid, or available funding is too
  incomplete for direction.

These are reason semantics, not additional dimension assessment states.

**Conditions producing alignment**

- a sufficiently complete, basis-compatible known or reviewed total-cost range
  fits within an explicit budget/constraint;
- verified funding already available to the student is included using the same
  net/gross basis;
- `STRONG_ALIGNMENT` requires complete material cost/funding coverage and
  meaningful room within a `REQUIRED` constraint.

**Conditions producing `MIXED`**

- comparable known cost supports affordability while a material known
  cash-flow or funding constraint contradicts it;
- some material cost periods/components align and others demonstrably do not,
  with sufficient coverage on both sides.

**`UNKNOWN` conditions**

- student budget or its basis is `UNSPECIFIED`;
- tuition and budget use incompatible scopes or currencies without a pinned
  conversion;
- material living cost, fees, funding, or aid uncertainty could reverse the
  conclusion;
- the distinction between gross cost and expected net cost is unresolved.

**Conditions producing misalignment**

- a comparable, sufficiently complete known cost violates a `REQUIRED`
  student budget constraint;
- a known required payment conflicts with an explicit hard funding constraint.

`MISALIGNMENT` must state whether it is a known mismatch. A potential mismatch
normally yields `MIXED` or `UNKNOWN`, depending on whether material supporting
evidence also exists.

**Evidence requirements**

- component-level cost provenance and completeness;
- academic year, currency, billing basis, and included-component scope;
- student budget/funding evidence and importance;
- source status for scholarships or aid.

**Cross-dimension exclusions**

Financial Fit does not own admission likelihood, career outcomes, expected
salary, ranking, or financial return prediction.

### 5.4 Geographic Fit

**Question answered**

> Does the program's location and delivery context align with the student's
> geographic preferences and location-dependent career goals?

**Allowed student inputs**

- explicit preferred, acceptable, required, and excluded locations with
  importance;
- willingness to relocate or study remotely;
- location-dependent career goals.

**Allowed program inputs**

- canonical program location, required attendance location, and delivery mode;
- verified campus/rotation/location structure.

**Allowed external/reviewed evidence**

- evidence-backed geographic recruiting context;
- reviewed geographic mappings and scoped labor-market context.

**Forbidden inputs**

- location preferences inferred from nationality or demographics;
- institutional location treated as proof of labor-market access;
- visa/work authorization or admission eligibility;
- prestige or ranking attached to a location.

**Deterministic comparisons**

- canonical program location versus required/excluded geography;
- delivery location versus explicit relocation/remote-study constraints.

**Permitted evidence-backed inference**

- evidence-backed relationship between location and a stated career geography;
- regional recruiting context with explicit applicability limits.

**Conditions producing alignment**

- canonical location/delivery directly satisfies a required or strongly
  preferred geography;
- evidence-backed location context supports an explicit career geography;
- `STRONG_ALIGNMENT` requires all material location/delivery constraints to
  align with no known material conflict.

**Conditions producing `MIXED`**

- location satisfies an academic/personal geography preference but applicable
  recruiting evidence contradicts an explicit career geography;
- multiple explicit geographic preferences receive material support and
  contradiction.

**`UNKNOWN` conditions**

- geographic preference is `UNSPECIFIED`;
- program delivery/location is unknown, hybrid, or insufficiently precise;
- career-geography evidence is indirect or conflicting.

**Conditions producing misalignment**

- program location violates an explicit `REQUIRED` or excluded geography;
- verified delivery requirements conflict with a required relocation
  constraint.

**Evidence requirements**

- exact program-version location/delivery facts;
- explicit student preference and importance;
- scoped evidence for inferred recruiting context.

**Cross-dimension exclusions**

Geographic Fit does not own international work authorization, financial cost,
career-outcome probability, or personal culture assumptions.

### 5.5 Personal Preference Fit

**Question answered**

> Do observable program characteristics align with preferences the student has
> explicitly expressed?

**Allowed student inputs**

- explicitly stated duration, delivery, schedule, format, and structure
  preferences;
- explicitly preferred academic setting;
- explicit preference importance.

**Allowed program inputs**

- canonical program duration, delivery mode, and schedule;
- cohort or class format when officially supported;
- thesis, capstone, internship, or research structure.

**Allowed external/reviewed evidence**

- reviewed interpretations of observable program characteristics;
- no inferred personality or psychographic evidence.

**Forbidden inputs**

- personality, culture, social comfort, or learning style inferred from
  unrelated behavior;
- demographic proxies;
- prestige, admission probability, or competitiveness;
- duplicate ownership of cost, geography, career, or international factors.

**Deterministic comparisons**

- duration range versus canonical duration;
- delivery/schedule preference versus canonical delivery/schedule;
- required thesis, capstone, internship, or research structure versus verified
  program structure.

**Permitted evidence-backed inference**

- evidence-backed interpretation of an observable program characteristic when
  it cannot be represented as direct equality.

**Conditions producing alignment**

- observable program characteristics satisfy explicit preferences;
- all `REQUIRED` preferences align and material strongly preferred
  characteristics are supported;
- `STRONG_ALIGNMENT` requires broad known support and no material
  contradiction.

**Conditions producing `MIXED`**

- meaningful explicit preferences are split between known supporting and
  contradicting program characteristics;
- no single required constraint conclusively dominates the dimension.

**`UNKNOWN` conditions**

- the preference is `UNSPECIFIED`;
- the relevant program characteristic is unknown or stale;
- no reviewed mapping/interpretation connects the preference to the fact.

**Conditions producing misalignment**

- an observable program characteristic violates an explicit `REQUIRED`
  preference;
- multiple sufficiently known characteristics materially contradict strongly
  preferred features.

**Evidence requirements**

- explicit preference and importance;
- accepted program-version fact;
- reviewed interpretation plus method/version when comparison is not direct.

**Cross-dimension exclusions**

Personal Preference Fit does not absorb financial, geographic, career,
international-accessibility, or eligibility judgments merely because they are
also personally important.

### 5.6 International Accessibility

**Question answered**

> For this international student, are there known structural accessibility
> differences in the program and its typical downstream paths involving visa
> context, employment authorization, professional licensing, or geographic
> restrictions?

**Allowed student inputs**

- authorized and necessary citizenship/status context;
- explicit target profession, geography, and downstream path;
- declared importance of international-access constraints.

**Allowed program inputs**

- STEM designation and CIP classification as source facts;
- international-student-relevant program structure and timing;
- program/location-specific work-authorization context where represented as an
  applicable reviewed fact;
- international career accessibility and sponsorship environment, with
  explicit population and geographic scope;
- verified professional-licensing or geographic restrictions;
- verified institutional support or structural constraints relevant to
  international students.

**Allowed external/reviewed evidence**

- current jurisdiction-specific work-authorization and OPT-related evidence;
- professional licensing restrictions;
- citizenship or security-clearance restrictions;
- geography-specific employment restrictions;
- reviewed international-access mappings with population, time, and path
  applicability.

Evidence authority is considered approximately in this order:

1. official government/regulatory evidence;
2. official university/program evidence;
3. reviewed structured external evidence;
4. applicable observational evidence;
5. model-generated inference.

This is authority guidance, not an automatic truth ranking. Evidence must also
match jurisdiction, time period, student context, program, and target
career/path where applicable. An authoritative source with the wrong
jurisdiction or validity period is not applicable.

STEM, CIP, or OPT-related facts are inputs. None directly implies high Fit.

**Forbidden inputs**

- whether the student can be admitted;
- prerequisites, application documents, or language requirements;
- applicant-category acceptance policies;
- admission probability or competitiveness;
- STEM designation treated as automatic `STRONG_ALIGNMENT`;
- general employment outcomes presented as international outcomes;
- unsupported immigration or legal advice.

US OPT rules do not determine accessibility for a UK program. Work
authorization does not imply employer sponsorship. Visa eligibility does not
imply visa approval probability. International Accessibility remains
structural-access assessment, not outcome prediction.

**Deterministic comparisons**

- a verified licensing/geographic restriction versus an explicit target
  profession/location;
- known program timing/authorization structure versus an explicit required
  path, only when the governing evidence is current and applicable.

**Permitted evidence-backed inference**

- international career accessibility from scoped sponsorship/employment
  evidence;
- structural opportunity/constraint assessment from multiple current sources;
- contextual interpretation with explicit legal and geographic limitations.

**Conditions producing alignment**

- current, applicable structural evidence supports access to the student's
  explicit target path without a known material restriction;
- multiple applicable access signals support the path and no material
  contradiction is known;
- STEM/OPT facts contribute only when connected to the student's jurisdiction,
  timing, and target path through reviewed evidence.

**Conditions producing `MIXED`**

- applicable authorization evidence supports one material part of the target
  path while licensing, clearance, sponsorship, or geographic evidence
  materially restricts another;
- meaningful supporting and restricting evidence applies to the same student
  context and path.

**`UNKNOWN` conditions**

- immigration/employment evidence is stale, jurisdictionally inapplicable, or
  not population-specific;
- the student's target geography/path is `UNSPECIFIED`;
- only STEM designation is known;
- general outcomes cannot be separated from international-student outcomes.

**Conditions producing misalignment**

- a current, applicable structural restriction conflicts with an explicit
  `REQUIRED` target profession, authorization path, or geography;
- sufficiently evidenced international accessibility constraints materially
  contradict the student's stated goals.

**Evidence requirements**

- jurisdiction, population, validity period, and source authority;
- student citizenship/status context only when authorized and necessary;
- explicit target profession/geography and importance;
- method/version for any inferred accessibility conclusion.

**Cross-dimension exclusions**

International Accessibility does not own admission eligibility, Career Fit,
Geographic Fit, or legal advice. Career Alignment owns role/industry relevance;
this dimension owns only international structural accessibility to those
paths.

## 6. Input contract

A Fit assessment is defined over exact, versioned inputs:

- frozen `student_profile_version`;
- exact `program_version`;
- taxonomy release and reviewed mappings;
- student goals and explicit preferences with declared importance;
- relevant student raw facts and evidence;
- canonical program facts and selected observations;
- applicable external/contextual metrics;
- optional pinned Phase 2 eligibility evaluation;
- Fit dimension-definition version;
- assessment-method version.

The Fit input manifest must identify every supplied record and mapping. It must
distinguish:

- a fact that was included;
- a fact that existed but was not supplied;
- a domain with incomplete coverage;
- a canonical program fact in an unknown, stale, or conflicting state.

Generic derived features may be used only when they have a versioned
definition, exact input manifest, provenance, and an explicit Fit use. They
never replace raw student or program facts.

### 6.1 Optional Phase 2 eligibility context

Fit may read a pinned Phase 2 result only to expose adjacent context:

- overall eligibility status;
- requirement-level gaps;
- requirement-level unknowns;
- exact eligibility evaluation/version reference.

This context is not a Fit signal. In v0.1:

- `NOT_ELIGIBLE` must not lower any Fit dimension;
- `UNKNOWN` must not lower confidence or assessment for an otherwise
  independently assessable Fit dimension;
- `ELIGIBLE` must not raise any Fit dimension;
- eligibility gaps must not become contradicting Fit reasons.

**Phase 2 eligibility status must not numerically or ordinally influence any
Fit dimension in v0.1.**

If an interface displays Eligibility and Fit together, it must preserve their
separate labels, reasons, versions, and provenance.

### 6.2 Fit mapping authority

Fit uses the Phase 2 normative mapping-state distinction:

- `PROPOSED`
- `VERIFIED`
- `REJECTED`
- `RETIRED`

Only active `VERIFIED` mappings are authoritative mapping inputs to a Fit
assessment. Mapping confidence is workflow metadata only and is never compared
with a threshold to grant authority.

A `MODEL` proposal may assist review but cannot become authoritative without
the required review and evidence process. Every Fit mapping decision retains
its purpose, provenance, proposal method, reviewer/review state where
applicable, and version information. Reusing a Phase 2 mapping does not permit
Fit to weaken or reinterpret its frozen authority.

## 7. Deterministic assessment and evidence-backed inference

### 7.1 Deterministic comparison

A conclusion may be deterministic when both sides are structured, compatible,
and sufficiently complete. Examples:

- preferred delivery mode versus canonical delivery mode;
- excluded geography versus program location;
- stated budget versus a sufficiently complete cost estimate with compatible
  currency, period, component scope, and gross/net basis;
- desired program-duration range versus canonical duration.

Deterministic does not mean evidence-free. Both compared values retain their
source and version.

### 7.2 Evidence-backed inference

Some dimensions require interpretation. Examples:

- curriculum alignment with a target career;
- strength of an academic-direction match;
- relevance of geographic recruiting context;
- international career accessibility.

An inference must record:

- the exact supporting and contradicting evidence;
- mapping and taxonomy versions;
- inference method and version;
- assumptions and applicability limits;
- missing inputs;
- confidence and evidence coverage.

Model-generated reasoning is derived output, not source data. An LLM statement
without traceable evidence cannot become a Fit conclusion. Similarity,
confidence, or model fluency must not be mistaken for verification authority.

### 7.3 Model-inference authority

Model inference is subordinate to authoritative facts and reviewed mappings.
Where a dimension contract permits it, model inference may generate a
supporting, contradicting, or unresolved signal, but:

- every inference pins its method/model version and exact evidence inputs;
- it cannot create or overwrite canonical program facts;
- it cannot create or overwrite student raw facts, goals, or preferences;
- it cannot turn an unknown source fact into a known fact;
- it cannot override a deterministic contradiction;
- it cannot alone produce `STRONG_ALIGNMENT`;
- its confidence is not Fit, admission, employment, or success probability.

For high-impact regulatory or accessibility conclusions, model-only evidence
cannot produce an authoritative positive or negative assessment. Without
authoritative, applicable evidence, International Accessibility returns
`UNKNOWN`.

## 8. Reason, confidence, and coverage semantics

Reasons are structured facts or evidence-bounded inferences, not generated
marketing prose. Each reason has:

- a stable code;
- direction: `SUPPORTING`, `CONTRADICTING`, or `LIMITING`;
- dimension;
- exact evidence references;
- applicability and population scope where relevant;
- method/version for inferred reasons.

Confidence reflects how defensible the conclusion is under the selected method
and available evidence. It may decrease because of:

- missing student preferences or goals;
- incomplete student or program coverage;
- stale or conflicting canonical observations;
- indirect or context-only evidence;
- unreviewed mappings;
- weak population applicability;
- inference-method limitations.

Evidence coverage describes how much of the required dimension input contract
is known, relevant, and usable. It is not a Fit score and is never used as a
hidden numerical threshold for a conclusion. Coverage and confidence must both
be explainable, but v0.1 defines no formula converting one into the other.

Coverage is categorical—`SUFFICIENT`, `PARTIAL`, or `INSUFFICIENT`. Fit v0.1
does not publish fake precision such as `73.4%` coverage. Each versioned
dimension method declares required versus optional evidence.

Confidence is categorical—`HIGH`, `MEDIUM`, or `LOW`—and records certainty in
the assessment under the evidence and inference method actually used.
Confidence is not a Fit, admission, employment, success, or outcome
probability. Each versioned dimension method governs confidence; there is no
universal formula. An assessment relying heavily on model inference cannot
silently receive the same confidence treatment as a deterministic comparison
of authoritative facts.

## 9. Provenance, persistence, and replay

Fit must preserve the Phase 1/2 separation between facts and derived output:

- program canonical facts remain in the catalog layer;
- student raw facts remain in the private student layer;
- Fit results remain derived, versioned assessments;
- Fit results never write back into canonical program or student columns.

Conceptually, the later data-model step should define:

- versioned Fit dimension definitions;
- versioned deterministic/inference methods;
- Fit evaluations pinned to student and program versions;
- normalized exact input manifests;
- one result per dimension;
- supporting, contradicting, and limiting evidence links;
- structured missing-input records;
- retirement/supersession without destructive history rewriting.

No tables or migrations are authorized by this specification alone.

A Fit evaluation conceptually contains one result for each of the six v0.1
dimensions. If required student intent or evidence is absent, the dimension is
persisted conceptually as:

```text
assessment = UNKNOWN
reason = STUDENT_PREFERENCE_UNSPECIFIED
```

or another stable missing-input reason. Dimensions are never silently omitted.
`UNKNOWN` remains distinct from neutral and poor Fit.

The same evidence may be referenced by multiple dimensions when legitimately
relevant:

```text
Evidence
  → Dimension-Specific Method/Interpretation
  → Fit Signal
```

Each dimension independently explains relevance under its own contract. STEM
designation may inform International Accessibility but does not automatically
improve Career or Academic Alignment. Program cost is naturally Financial
evidence, not Academic evidence. Eligibility prerequisite gaps remain adjacent
Phase 2 context and never become negative Academic Fit evidence.

Replay is available only while the referenced student-owned data exists.
Privacy deletion must remove dependent Fit manifests and results. Catalog
history remains durable. Fit must not retain copied private facts in a global
audit trail to bypass deletion.

## 10. Relationship to downstream products

Fit v0.1 is an assessment substrate, not a recommendation engine.

A future recommendation layer may combine:

- Eligibility;
- Fit dimensions;
- Competitiveness;
- confidence and evidence coverage;
- student strategy and portfolio constraints.

That future layer requires its own versioned semantics. It must not treat
`STRONG_ALIGNMENT`, `ALIGNMENT`, `MIXED`, or `MISALIGNMENT` as calibrated
admission likelihood.

### 10.1 Fit v0.1 MVP exclusions

This specification does not authorize:

- a total Fit Score;
- numeric dimension or preference weights;
- learned preference weights;
- recommendation ranking;
- Reach/Target/Safer labels;
- competitiveness assessment;
- admission probability;
- portfolio strategy;
- inferred personality or psychographics;
- unsupported career-outcome prediction;
- Phase 3 database migrations;
- a Fit evaluator or implementation code.

This revision is semantic hardening only.

## 11. Conceptual data flow

```text
Phase 1 Program Facts + Evidence
                │
                ├──────────────┐
                │              │
Phase 2 Student Profile    Phase 2 Eligibility
                │              │
                └──────┬───────┘
                       │ frozen upstream contract
                       ▼
             Exact Fit Input Manifest
                       │
          ┌────────────┴────────────┐
          │                         │
 Deterministic Comparisons   Evidence-backed Inference
          │                         │
          └────────────┬────────────┘
                       ▼
          Per-dimension Fit Results
  assessment + reasons + confidence + coverage
                       │
             no score, rank, or probability
```

## 12. MVP semantic test cases

The later implementation must cover at least:

1. **Eligible but financially misaligned**
   Eligibility remains `ELIGIBLE`; sufficiently complete, basis-compatible
   known cost exceeds a `REQUIRED` budget, producing Financial Fit
   `MISALIGNMENT` with traceable comparison inputs.

2. **Unknown Eligibility but assessable Geographic Fit**
   Eligibility remains `UNKNOWN`; program location directly matches an
   explicit preference, producing a separate Geographic Fit `ALIGNMENT`.

3. **Missing preference data**
   A student has no financial constraint or geographic preference. The
   corresponding dimensions return `UNKNOWN`, not `ALIGNMENT` or
   `MISALIGNMENT`.

4. **Conflicting program evidence**
   Conflicting or stale program characteristics cannot produce a
   high-confidence directional conclusion.

5. **Deterministic mismatch**
   A student marks in-person delivery `REQUIRED` and the canonical program mode
   is online. Personal Preference Fit is `MISALIGNMENT` with traceable reasons;
   Phase 2 eligibility is unchanged.

6. **Evidence-backed career inference**
   Reviewed curriculum/career mappings support alignment, but outcome evidence
   is sparse or population-inapplicable. Career Fit exposes the limitation and
   cannot claim employment probability.

7. **International boundary attack**
   STEM/OPT context may support International Accessibility, but a prerequisite
   or applicant-category policy is rejected as a Fit input and remains in
   Eligibility.

8. **Mapping-authority attack**
   A high-confidence model-proposed mapping cannot support a directional Fit
   conclusion unless it satisfies the separately specified Fit mapping
   authority.

9. **Probability leakage attack**
   No conclusion, reason, confidence, or output field may be described as
   admission probability, Reach/Target/Safer, or predicted acceptance.

10. **Input-order determinism**
    Equivalent exact manifests produce the same assessment regardless of row
    order; changing an exact evidence or mapping decision changes the
    fingerprint.

11. **Privacy deletion**
    Deleting student-owned data removes dependent Fit inputs and results and
    intentionally ends replayability.

12. **No composite-score leakage**
    The output contains only dimension conclusions; no hidden or persisted
    total score is computed.

13. **Hard versus soft preference**
    The same program conflict produces a stronger reason when importance is
    `REQUIRED` than when it is `PREFERRED`, without converting importance into
    a numeric weight or changing Eligibility.

14. **True mixed evidence**
    Material supporting and contradicting evidence produces `MIXED`. Missing
    evidence without a contradiction produces `UNKNOWN`, never `MIXED`.

15. **Unknown affordability**
    Tuition exceeds a nominal budget, but budget scope, living cost, and aid
    are incomplete. The result records potential mismatch and returns
    `UNKNOWN` rather than permanent financial misalignment.

16. **Career evidence-authority attack**
    A program name, curriculum similarity, or model-generated career
    hypothesis cannot by itself produce `STRONG_ALIGNMENT` or `HIGH`
    confidence.

17. **Eligibility-influence attack**
    Holding Fit inputs constant while changing only the adjacent Phase 2 status
    among `ELIGIBLE`, `NOT_ELIGIBLE`, and `UNKNOWN` does not change any Fit
    assessment, confidence, or coverage.

18. **STEM shortcut attack**
    STEM designation alone cannot produce International Accessibility
    `STRONG_ALIGNMENT`; missing jurisdictional and student-path context yields
    `UNKNOWN`.

19. **Not eligible but academically aligned**  
    A pinned Phase 2 result is `NOT_ELIGIBLE`, while reviewed curriculum
    evidence strongly supports the student's stated study goals. Academic
    Alignment remains `STRONG_ALIGNMENT`; the eligibility result is displayed
    separately and does not lower Fit.

20. **Missing program information**  
    A required program characteristic is unknown or stale. The affected
    dimension returns `UNKNOWN`, not `MISALIGNMENT`.

21. **Prestige and GPA leakage attacks**  
    Increasing institutional prestige or student GPA while holding valid Fit
    inputs constant does not improve any dimension. GPA and admission-test
    performance do not alter Academic Alignment.

22. **Incompatible financial scopes**  
    Tuition-only program cost and a total-annual student budget cannot produce
    deterministic Financial `MISALIGNMENT`. Missing fees, living costs,
    currency/period alignment, and funding context produce `UNKNOWN` or a
    scoped limiting reason.

## 13. Final v0.1 semantic decisions

The prior 11 data-model blockers are resolved as follows:

1. **Within-dimension combination**  
   Versioned dimension methods evaluate material signals categorically. There
   is no numeric aggregation, weighting, vote, percentage, or hidden point
   system.

2. **Required-constraint precedence**  
   A confirmed comparable contradiction of a student-declared `REQUIRED`
   constraint produces `MISALIGNMENT` in its owning dimension. Unknown or
   incomparable program facts produce `UNKNOWN`.

3. **Strong versus ordinary alignment**  
   `STRONG_ALIGNMENT` requires the dimension method's explicit higher evidence
   bar: multiple material positives or authoritative strong satisfaction of a
   directly comparable high-importance intent, with no material contradiction.
   Model inference alone and prohibited signals cannot qualify.

4. **Dimension coverage contract**  
   Coverage is `SUFFICIENT`, `PARTIAL`, or `INSUFFICIENT`. Each method declares
   required versus optional evidence. Core insufficient evidence normally
   produces `UNKNOWN`; unrelated optional missingness does not block an
   otherwise supportable assessment.

5. **Confidence governance**  
   Confidence is `HIGH`, `MEDIUM`, or `LOW`, governed by each versioned method
   and kept separate from coverage. It is not a probability, and no universal
   coverage-to-confidence formula exists.

6. **Fit mapping authority**  
   Fit uses `PROPOSED`, `VERIFIED`, `REJECTED`, and `RETIRED`; only active
   `VERIFIED` mappings are authoritative. Confidence never grants authority,
   and model proposals require review/evidence.

7. **Model-inference authority**  
   Model inference may contribute a versioned, evidence-linked signal where a
   dimension contract allows it. It cannot alter facts, resolve unknown source
   facts, override deterministic contradiction, or alone produce
   `STRONG_ALIGNMENT`. Model-only evidence is insufficient for high-impact
   International Accessibility conclusions.

8. **Financial comparability**  
   Deterministic comparison requires compatible currency/basis, period, scope,
   and components. Required normalization must use a pinned approved versioned
   method; otherwise the assessment is `UNKNOWN`. Unknown financial quantities
   are never invented.

9. **International evidence governance**  
   Evidence follows the documented authority guidance and must match
   jurisdiction, time, student context, program, and path. Structural
   accessibility is not visa, employment, or outcome probability.

10. **Unspecified-dimension persistence**  
    Every evaluation conceptually contains all six dimension results. Missing
    intent/evidence persists as `UNKNOWN` with a stable missing-input reason;
    the dimension is not omitted.

11. **Cross-dimension evidence ownership**  
    Evidence may be referenced by multiple dimensions through separate
    dimension-specific methods and interpretations. Each dimension must justify
    relevance, and prohibited signals cannot leak across contracts.

No semantic blocker remains from this list.

## 14. Acceptance criteria for the data-model design

The next Phase 3 design step may begin only when:

- every dimension has one clear product question and explicit exclusions;
- each input is owned by an existing authoritative layer or identified as a
  new derived/contextual contract;
- deterministic and inferred methods are distinguishable;
- assessment, confidence, coverage, and method remain separate;
- hard constraints and soft preferences retain explicit importance without
  hidden weights;
- missing and conflicting evidence behavior is explicit;
- exact provenance and replay requirements are defined;
- privacy deletion is preserved;
- no aggregate score, ranking, competitiveness, or probability is introduced;
- no frozen Phase 2 migration or semantic contract is modified;
- adversarial boundary tests cover Eligibility, Competitiveness, admission
  probability, recommendation ranking, mapping authority, `UNKNOWN`, aggregate
  scoring, and privacy deletion.

The next deliverable is a Fit data-model proposal. It is not an implementation
authorization.
