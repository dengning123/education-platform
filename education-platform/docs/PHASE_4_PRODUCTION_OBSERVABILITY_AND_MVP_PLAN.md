# Phase 4 Production Observability and Minimum Product Loop Plan

Status: **PLANNING ONLY — IMPLEMENTATION NOT YET AUTHORIZED**

Date: 2026-08-22

Frozen baseline: commit `55296e1aeca9a25b066e9010c376f0e618af59d1`,
tag `phase3-fit-v0.1`

Related data-contract plan:
[`MIGRATION_019_APPLICATION_OUTCOME_CONTRACT_PLAN.md`](MIGRATION_019_APPLICATION_OUTCOME_CONTRACT_PLAN.md)

## 1. Objective

Phase 4 turns the verified Phase 3 backend into a safely operated, minimally
usable product loop. It has two immediate workstreams:

1. production observability, incident response, and release safety for the
   existing Eligibility/Fit services;
2. a thin authenticated user experience from student data intake through
   Eligibility, six-dimensional Fit, Financial review, and privacy deletion.

Application tracking and verified outcome collection join the product loop
only after the separately reviewed Migration 019 contract is implemented.

Phase 4 does not change the frozen meanings of Eligibility or Fit. It does not
implement Competitiveness, admission probability, ranking, recommendation, or
learned weights.

## 2. Frozen semantic boundaries

- Eligibility answers whether explicit program requirements are satisfied,
  not whether admission is likely.
- Fit reports six independent categorical preference/constraint assessments,
  confidence, evidence coverage, and limiting reasons.
- The UI must not combine Fit dimensions into a total score.
- `UNKNOWN`, missing evidence, verified mismatch, and pending review are
  visibly distinct states.
- Financial `AVAILABLE_FUNDING` is never interpreted as a cost ceiling.
- Only frozen profile, intent, catalog, evaluation, and normalization versions
  may be displayed as completed results.
- No client or service may bypass SQL finalizers, ownership checks, review
  requirements, or fingerprints.

## 3. Delivery sequence

### 3.1 Phase 4A — observability foundation

Introduce one shared Edge request wrapper used by all four existing Fit
functions and every new Phase 4 endpoint. It must provide:

- a generated UUID request ID, returned in `x-request-id` and the closed error
  envelope;
- an allowlisted structured event schema;
- monotonic request-duration measurement;
- exact endpoint, deployed release/build identity, HTTP status class, and
  stable error code;
- consistent mapping of authentication, authorization, lifecycle conflict,
  validation, dependency, and internal failures;
- automatic redaction before an event leaves the process.

The first observability implementation is service-level. Migration 019 is
reserved for Application/Outcome semantics. Any durable database operation
receipt or trace table requires a separate additive migration after 019.

#### Allowed operational event fields

- request ID;
- function/endpoint code;
- deployed release and build hash;
- stage code such as `AUTH`, `LOAD`, `ASSEMBLE`, `FINALIZE`, or `RESPONSE`;
- HTTP status and stable error code;
- duration in milliseconds;
- cold-start indicator when provided by the runtime;
- retry count and idempotency result as bounded enums;
- deployment region/runtime version when provided by the platform.

#### Forbidden operational event fields

- Authorization headers, API keys, JWTs, passwords, cookies, or raw claims;
- email, name, document contents, student-entered free text, or evidence
  excerpts;
- request or response bodies;
- profile, student, evaluation, normalization, application, evidence, or
  observation UUIDs in infrastructure logs;
- unhashed storage paths or database connection strings;
- Fit reasons, financial amounts, outcome values, or eligibility results in
  generic infrastructure logs.

Short-lived request IDs may correlate client-visible failures with runtime
events. Student-linked audit data remains inside student-owned database rows
and must disappear through privacy deletion; it must not be copied into the
global operational log stream.

### 3.2 Metrics, dashboards, and alerts

Initial dashboards must expose aggregates only:

- request count, success rate, and latency percentiles by endpoint/release;
- 401, 403/404, 409, 422, and 5xx counts by stable error code;
- Fit evaluations started, completed, failed closed, and left `BUILDING`;
- Financial normalizations prepared, verified, rejected, resumed, and left
  `DRAFT`;
- privacy deletion attempts, successes, and integrity failures;
- deployment version skew between the four Edge Functions;
- database connection/RPC failure rate and retry behavior.

Immediate paging conditions:

- any privacy-deletion integrity failure;
- any deployed function missing its expected build identity;
- sustained 5xx rate above 1% with at least five requests in five minutes;
- a release producing three consecutive internal failures during canary smoke;
- any completed evaluation with a missing or malformed fingerprint.

Operational review conditions:

- a `BUILDING` evaluation older than 15 minutes;
- a Financial normalization left `DRAFT` for more than 72 hours;
- repeated authorization failures from one runtime/client class;
- p95 latency regression greater than 50% against the preceding verified
  release baseline.

Numeric service-level objectives are ratified only after a seven-day clean
baseline. The initial proposed availability objective is 99.5%, excluding
caller-caused 4xx responses and planned maintenance.

### 3.3 Retention and access

- raw runtime events: shortest operationally useful retention, initially no
  more than 14 days;
- aggregated metrics: may be retained longer only when they contain no stable
  user or object identifier;
- production log access: restricted to the operations role and audited;
- export to third-party monitoring: disabled until the redaction fixture suite
  passes against representative failures;
- no production payload capture, replay recording, or session recording.

## 4. Phase 4B — minimum product loop

### 4.1 Primary user flow

```text
Authenticated student
→ create/edit DRAFT profile
→ see domain completeness and evidence gaps
→ freeze profile snapshot
→ declare goals/preferences and freeze Fit intent set
→ choose one exact program version
→ run Eligibility v0.2
→ run Fit v0.1
→ if required, prepare Financial normalization
→ independent reviewer verifies or rejects
→ student resumes the same evaluation
→ inspect six categorical Fit dimensions and evidence limitations
→ optionally create an application record after Migration 019
→ export or delete student data
```

### 4.2 Required screens

1. Sign-in and account-state screen.
2. Profile intake with explicit completeness by domain.
3. Evidence and mapping review status.
4. Goals/preferences and Fit-intent confirmation.
5. Program-version selection showing cycle and source freshness.
6. Eligibility result with requirement tree and `UNKNOWN` explanations.
7. Fit result with exactly six dimension cards.
8. Financial normalization pending/reviewed/resumed state.
9. Privacy/export controls.
10. Application tracker and outcome reporting only after Migration 019.

### 4.3 Result presentation rules

- Eligibility and Fit occupy separate sections and use different visual
  language.
- Fit cards show assessment, confidence, evidence coverage, reasons, and
  limiting inputs; no numeric visualization suggests a hidden score.
- `UNKNOWN` must name the missing or inadmissible evidence family.
- Pending Financial review must never display a provisional completed Fit
  result.
- An expired/retired source is shown as historical provenance, not silently
  replaced by current live data.
- The interface never generates Reach/Target/Safer labels.

### 4.4 API boundary

The browser receives only owner-readable data. Mutations go through closed,
typed RPCs or Edge endpoints that:

- authenticate the user and recheck ownership server-side;
- reject unknown keys and arbitrary JSON payload extensions;
- use client request UUIDs for safe retry/idempotency;
- call the existing controlled database functions and finalizers;
- return stable error codes plus request ID, never internal SQL details;
- avoid placing the service-role credential in the browser.

New API surface is grouped by capability rather than one endpoint per table:

- profile draft/freeze orchestration;
- intent draft/freeze orchestration;
- Eligibility v0.2 evaluation orchestration;
- the existing Fit and Financial endpoints;
- privacy export/deletion orchestration;
- Application/Outcome commands after Migration 019.

### 4.5 Reviewer flow

The reviewer experience is separate from the student experience. It must:

- require the exact capability claim for the review domain;
- hide unrelated students and unrelated review queues;
- prevent the submitter from reviewing the same artifact;
- display only the minimum evidence needed for the decision;
- record a typed decision and reason code, not unrestricted notes;
- never reuse `fit_normalization_reviewer` for application-outcome review.

## 5. Security and privacy gates

- owner and unrelated-user RLS tests for every screen query;
- no direct external DML on student, evaluation, normalization, application,
  or outcome tables;
- CSRF/CORS and origin policy reviewed before browser rollout;
- rate limits for evaluation, review, and deletion commands;
- payload size limits and content-type enforcement;
- privacy deletion exercised against the complete Phase 4 table inventory;
- evidence/document storage either excluded from the MVP or covered by an
  explicit storage-deletion transaction/runbook;
- no raw document, profile, outcome, or financial content in telemetry.

## 6. Release and rollout gates

### Gate A — observability canary

- shared wrapper unit tests and redaction attack corpus pass;
- all existing anonymous/authenticated remote smoke remains green;
- dashboards identify function version, failures, latency, and stale work;
- a synthetic failure produces a request ID without leaking payload data;
- rollback to the Phase 3 tagged functions is documented and rehearsed.

### Gate B — internal minimum loop

- one student completes profile → Eligibility → Fit end to end;
- one independent reviewer completes Financial review;
- retries are idempotent and do not duplicate evaluations;
- unrelated-user and self-review attacks fail;
- privacy deletion removes the entire student-owned loop.

### Gate C — limited production rollout

- canary users only, behind a server-side feature flag;
- no unresolved severity-1/2 security or privacy findings;
- seven-day observability baseline collected;
- support and incident runbooks approved;
- the Phase 3 semantic-exclusion scan still rejects score, weight, ranking,
  probability, recommendation, Competitiveness, and Eligibility leakage into
  Fit responses.

### Gate D — Application/Outcome enablement

- Migration 019 receives independent design approval and implementation
  authorization;
- clean `001→019`, populated `018→019`, RLS, concurrency, privacy, and remote
  smoke gates pass;
- outcome evidence/reviewer policy and research-consent copy are approved;
- no Competitiveness training or inference job exists.

## 7. Test matrix

- request/error envelope and unknown-key rejection;
- telemetry allowlist and secret/PII redaction;
- authenticated owner, unrelated user, anonymous, reviewer, and service-role
  boundaries;
- duplicate request/retry behavior;
- incomplete profile and intent freeze rejection;
- Eligibility v0.2 and Fit v0.1 version mismatch rejection;
- all six Fit dimensions and every `UNKNOWN` presentation state;
- Financial prepare/review/resume, self-review rejection, retired input, and
  stale review attacks;
- network timeout after commit followed by safe retry;
- deployment rollback and mixed-function-version detection;
- privacy deletion during evaluation/review;
- accessibility keyboard, screen-reader, contrast, and mobile-width checks.

## 8. Explicit non-goals

- Competitiveness schema, features, model training, or inference;
- learned weights or student-level probabilities;
- program ranking, portfolio optimization, or recommendations;
- generalized workflow/plugin framework;
- arbitrary analytics event collection;
- raw request/session replay;
- changes to migrations `001`–`018` or the frozen Phase 3 evaluator identity.

## 9. Authorization boundary

This document records the Phase 4 implementation plan only. It does not
authorize code, infrastructure, dashboard, UI, migration, storage, monitoring
vendor, or production rollout changes. Each implementation increment starts
only after its scope and mutation authority are separately approved.
