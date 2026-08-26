# Market-Evidence Product Capability Matrix

Status: **FORWARD-LOOKING PRODUCT PRIORITIZATION — NOT IMPLEMENTATION AUTHORIZATION**

Date: 2026-08-24

## 1. Purpose and interpretation

This matrix aligns the education platform roadmap to the decisions made by a
Chinese undergraduate or university-background student considering United
States graduate programs. The product thesis is:

> **Evidence-Based Graduate Education Decision Intelligence**

The product should help a student identify realistic programs, understand
Eligibility and multidimensional Fit, see why a conclusion was reached, find
missing or uncertain evidence, compare material tradeoffs, and form a
defensible shortlist. It is not a generic AI chatbot, an agency workflow
clone, a ranking site, or an unsupported admission-probability generator.

The ratings below are product-prioritization judgments grounded in the cited
external evidence and the repository's executable coverage. They are not
objective market statistics, model features, model weights, or student-level
scores. `High`, `Medium`, and `Low` are ordinal planning labels only.

Priority tiers mean:

- **NOW:** needed to complete and validate the core Profile → Eligibility →
  Fit decision loop or to make its evidence understandable and safe;
- **NEXT:** high-value decision support to add after the core loop and a real
  program-data audit are trustworthy;
- **LATER:** valuable lifecycle or context capability that does not block the
  first decision loop;
- **DEFERRED:** evidence or data prerequisites are not yet sufficient for a
  truthful product claim.

## 2. Capability matrix

| Capability | Market demand | Decision importance | Frequency | Solution gap | Data availability | Differentiation potential | Current platform coverage | Current gap | Priority tier | Evidence sources | Implementation status |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Student Profile | High | High | Repeated setup/update | Medium | Student-supplied, evidence-dependent | High | Versioned draft/freeze/fork foundation and completeness contracts | Complete real authenticated flow and Chinese-background audit | NOW | E02, E09 | Local product/backend foundation; full real E2E pending |
| Program Data | High | High | Repeated across every decision | High | Fragmented across official program pages and public datasets | High | Versioned catalog, provenance, one golden-record foundation | Validate breadth, freshness, and representability on real programs | NOW | E02, D01, D02, D03 | Foundation present; representative coverage not proven |
| Program Discovery | High | High | Repeated early-stage | Medium | Institution/program facts available but fragmented | Medium | Exact program-version selection, no discovery product | Evidence-backed filters and candidate-set construction | NEXT | E02, E05, D01, D02 | Not implemented |
| Eligibility | High | High | Every candidate-program pair | High | Official requirements exist but vary in structure and clarity | High | Frozen deterministic Eligibility v0.2, evidence and unknown states | Full browser flow plus broader real-program rule coverage | NOW | E02, D01 | Backend semantics implemented; product/data coverage incomplete |
| Academic Fit | High | High | Every candidate-program pair | High | Curriculum and prerequisite evidence vary by program | High | Categorical Fit foundation, course/evidence mappings, explanation | Broader curriculum evidence and real-program validation | NOW | E02, E05, D01 | Semantic foundation implemented; breadth pending |
| Career Fit | High | High | Every serious comparison | High | Program claims, occupational data, and outcomes differ in scope | High | Categorical Fit dimension and career taxonomy foundation | Evidence-backed pathways, skills, employers, internships, outcomes | NOW | E05, E06, E07, E08, D03, D04 | Semantic foundation implemented; outcome evidence thin |
| Financial Decision Support | High | High | Every serious comparison | High | Tuition/fees are available but billing basis, duration, and living cost vary | High | Financial Fit and reviewed normalization foundation | Total academic cost, duration, living context, funding, uncertainty | NOW | E03, E05, E07, E08, D01, D02 | Bounded foundation implemented; full cost picture missing |
| Scholarship / Funding | High | High | Search and final choice | High | Program-specific and often conditional or incomplete | High | Funding remains semantically separate from cost ceiling | Verified scholarships, assistantships, eligibility, amount/basis/freshness | NEXT | E03, E05, E08, D01 | Partial semantic coverage; product evidence coverage missing |
| Career Outcomes | High | High | Comparison and final choice | High | Public aggregates exist; program/international granularity is uneven | High | Provenance and population-scope foundations | Program-linked pathways, occupations, employment, salary, internships, employers, and international constraints | NEXT | E05, E06, E07, E08, D03, D04 | Not implemented as a product capability |
| ROI / Value | High | High | Comparison and final choice | High | Inputs exist at mixed scope and quality | High | Separate cost, Fit, confidence, and provenance foundations | Present cost, duration, funding, career evidence, and uncertainty without a false composite score | NEXT | E03, E07, E08, D03, D04 | Not implemented; no ROI formula authorized |
| International Accessibility | High | High | Every international-student decision | High | Official policy plus program/institution facts; high freshness burden | High | International-accessibility Fit dimension and evidence architecture | Independent source-backed domain for study/work accessibility and uncertainty | NOW | E01, E04, E07, D05 | Semantic foundation only; policy evidence product incomplete |
| STEM / OPT Context | High | High | Program screening and comparison | High | Official lists exist; exact program CIP and current status require verification | High | Program versioning can hold time-sensitive facts | Exact program/CIP evidence, source date, applicability, change detection | NEXT | E01, E04, D01, D05 | Partial catalog concept; verified product coverage missing |
| Location / Geography | Medium | Medium | Screening and comparison | Medium | Generally available; living/career implications vary | Medium | Geographic Fit dimension | Evidence-backed cost, recruiting, and student preference context | NOW for basic Fit; LATER for lifestyle depth | E03, E07, D01 | Basic semantic coverage; advanced context deferred |
| Delivery / Duration | High | High | Screening, cost, and comparison | Medium | Usually published, but format and completion assumptions vary | Medium | Personal-preference Fit and program-version foundation | Verified duration, modality, intensity, and cost interaction | NOW | E03, E08, D01, D02 | Partial coverage |
| Reputation Context | High for target segment | Medium | Screening and comparison | Low | Ranking data are available but methodologically heterogeneous | Low | No ranking optimization | Bounded contextual evidence without turning reputation into product objective | LATER | E02, E06, E07 | Not implemented; global ranking product explicitly excluded |
| Curriculum Comparison | High | High | Shortlisting and final choice | High | Official curricula exist but change by cycle and use inconsistent labels | High | Course taxonomy, mappings, program versioning, Academic Fit | Real-program course coverage and side-by-side semantic comparison | NOW foundation; NEXT product | E02, E05, E06, D01 | Foundations partial; comparison not implemented |
| Prerequisite Equivalency | High | High | Eligibility and gap remediation | High | Requires student evidence and reviewed semantic mapping | High | Rule trees, evidence, reviewed mappings, completeness contracts | Chinese course-title/equivalency validation at representative scale | NOW | E02, E09, D01 | Strong foundation; target-student audit pending |
| Program Comparison | High | High | Repeated shortlist formation | High | Depends on normalized evidence across all decision domains | High | Domain outputs exist independently; no comparison surface | Side-by-side evidence, reasons, unknowns, cost, career and international tradeoffs | NEXT | E02, E05, E07, D01, D03 | Not implemented |
| Shortlist | High | High | Repeated until application set stabilizes | High | Depends on trustworthy discovery/comparison inputs | High | No shortlist product | Save/organize by Eligibility, Fit, cost, career, international, geography and uncertainty without ML ranking | NEXT | E02, E05 | Not implemented |
| Evidence / Provenance | High implicit trust need | High | Every displayed claim | High | Source-specific | High | Canonical facts, observations, applicability, freshness and audit foundations | Scale verification workflow and expose bounded evidence context in product | NOW | E02, E04, D01, D02, D03, D05 | Strong foundation; product/data breadth incomplete |
| Confidence / Uncertainty | High implicit trust need | High | Every incomplete or time-sensitive decision | High | Derived from evidence coverage/freshness, not guessed | High | Categorical confidence, evidence coverage, explicit unknown states | Consistent cross-domain presentation and freshness handling | NOW | E02, E04, D01 | Implemented in bounded semantics; broader product consistency pending |
| Explanation | High | High | Every result review | High | Depends on typed rules and cited evidence | High | Evidence-backed reasons and limiting inputs | Cross-domain, comparison-ready explanations without generated authority | NOW | E02, E05 | Bounded Eligibility/Fit support implemented |
| Competitiveness / Admission Probability | High stated interest | High if valid | Application portfolio stage | Very high | Insufficient verified program/cycle outcomes | Potentially high, currently unsafe | Architecture note and future Application/Outcome plan only | Representative snapshots, verified outcomes, calibration and bias controls | DEFERRED | E01, E09 | Not implemented or authorized |
| Application Tracking | Medium | Medium after shortlist | Seasonal/repeated | Medium | Student-supplied operational data | Medium; strategically useful for future outcomes | Provisional Migration 030 plan only | Complete decision loop first; separately review and implement later | LATER | E09 | Planning-only; no SQL/runtime |
| Offer Comparison | Medium | High for admitted students | Low-frequency, high-stakes | High | Student-specific offers and verified costs vary | High | No product capability | Compare actual funding, cost, conditions, career and international tradeoffs | LATER | E03, E04 | Not implemented |

## 3. Evidence registry and scope limits

Market-demand evidence:

- **E01 — IIE Open Doors 2025:** international-student scale, graduate-level
  movement, China origin population, STEM and OPT participation.
  <https://www.iie.org/news/open-doors-2025-press-release/>
- **E02 — EducationUSA, Research Your Options (Graduate):** the official
  student journey begins with broad program research and explicitly rejects a
  single official ranking as the definition of best fit.
  <https://educationusa.state.gov/your-5-steps-us-study/research-your-options/graduate>
- **E03 — EducationUSA, Finance Your Studies (Graduate):** total budgeting
  includes tuition, fees and living expenses; scholarships and assistantships
  require program-specific research.
  <https://educationusa.state.gov/your-5-steps-us-study/finance-your-studies/graduate>
- **E04 — EducationUSA, Apply for Your Student Visa (Graduate):** study access
  depends on program acceptance, SEVP status and current government rules.
  <https://educationusa.state.gov/your-5-steps-us-study/apply-your-student-visa/graduate>
- **E05 — QS International Student Survey 2024, US and Canada:** teaching
  quality, affordability/scholarships, graduate employment, skills, networks
  and work placements are material decision factors for surveyed students.
  <https://www.qs.com/insights/how-can-american-and-canadian-universities-recruit-more-international-students-in-2024>
- **E06 — QS 2024 APAC/China analysis:** surveyed Chinese prospects place
  material weight on reputation and employment-linked experience. This is
  segment evidence, not authorization to optimize rankings.
  <https://www.qs.com/insights/rethinking-international-student-recruitment-in-the-apac-region>
- **E07 — QS Global Student Flows 2025:** cost of living, employment, graduate
  outcomes, destination welcome and post-study considerations remain material
  international-student concerns.
  <https://www.qs.com/insights/global-student-flows-report>
- **E08 — GMAC Prospective Students Survey 2025:** career outcomes, ROI,
  program cost, financial aid, program format and mobility affect graduate
  management candidates. This evidence is business-education-specific and is
  not treated as representative of every graduate discipline.
  <https://www.gmac.com/market-intelligence-and-research/research-library/admissions-and-application-trends/2025-gmac-prospective-students-survey-summary-report>
- **E09 — Current platform executable evidence:** frozen Profile,
  Eligibility, Fit, Financial, provenance, privacy, and planned
  Application/Outcome contracts in this repository. Executable coverage is
  evidence of correctness and scope, not evidence of market demand.

Candidate implementation-data sources:

- **D01 — official university program, admissions, curriculum, tuition,
  international-office and career-outcome pages:** primary source for the
  exact program and cycle; each claim still needs applicability and freshness.
- **D02 — NCES IPEDS:** institution and program-completion, tuition, delivery,
  enrollment and related public data, with explicit release-year and
  granularity limits. <https://nces.ed.gov/ipeds/use-the-data>
- **D03 — U.S. Department of Education College Scorecard:** public cost, debt,
  completion and earnings data, including field-of-study data where released;
  population and institution/program granularity must remain visible.
  <https://catalog.data.gov/dataset/college-scorecard>
- **D04 — U.S. Bureau of Labor Statistics Occupational Outlook Handbook:**
  occupation duties, education, pay and outlook; it is occupational context,
  not a program-specific placement claim. <https://www.bls.gov/ooh/>
- **D05 — DHS Study in the States / SEVP sources:** certified-school and STEM
  designated-degree evidence. Exact program CIP, student eligibility and
  current policy still require source-backed applicability checks.
  <https://studyinthestates.dhs.gov/school-search>

External sources have different populations, years, and commercial or public
purposes. No single source proves a product priority. The matrix uses them as
triangulated directional evidence and requires the real-data audits below
before an implementation abstraction is accepted.

## 4. Real-data validation strategy

### Stage 1 — representative audit

Audit 10–20 real United States graduate programs across:

- Computer Science, Data Science, and Statistics;
- Engineering;
- Business and Analytics;
- Economics and quantitative programs.

For each exact program version, audit requirements, prerequisites, tests,
tuition and billing basis, duration, curriculum, STEM/OPT evidence,
international requirements, career evidence, scholarships/funding, deadlines,
and provenance. Classify each required fact as:

- `SUPPORTED`
- `PARTIAL`
- `UNKNOWN`
- `UNREPRESENTABLE`

### Stage 2 — breadth audit

After Stage 1 gaps are understood, expand to 50–100 programs. A new schema,
migration, RPC, engine, or generalized framework is justified only when a
repeated real-data gap cannot be represented safely by the existing contract.

### Target-student audit

Test the existing Profile and mapping contracts against representative Chinese
student backgrounds: institution and degree names, majors, GPA/percentage
systems, bilingual course titles, course equivalency, tests, international
requirements, cost constraints, STEM/OPT goals, and U.S./China career intent.
This audit does not authorize new fields in advance.

## 5. Foundation-entry rule

New foundation work enters the roadmap only when at least one condition is
mechanically supported:

1. a high-priority market decision and real-data evidence require it;
2. the current executable product path is blocked without it;
3. it closes a confirmed correctness, security, or privacy defect; or
4. repeated representative data is otherwise unrepresentable.

Otherwise, defer it. Market evidence decides **what** deserves priority, real
student/program evidence decides **how** it should be modeled, and executable
evidence proves whether the result is correct.

## 6. Non-authorization boundary

This matrix does not authorize code, schema, migration, RPC, UI, ingestion,
deployment, scraping, data collection, model training, scoring, ranking, or
probability output. It does not change frozen Eligibility, Fit, Financial,
evaluator, fingerprint, privacy, or evidence semantics.
