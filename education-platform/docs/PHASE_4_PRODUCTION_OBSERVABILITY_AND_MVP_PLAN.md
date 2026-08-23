# Phase 4 Production Observability and Minimum Product Loop Plan

Status: **PHASE 4A-1 FINAL FREEZE — PHASE 4A-2 READINESS FINDINGS ONLY,
AUTOMATION NOT AUTHORIZED**

Date: 2026-08-22

Frozen baseline: commit `55296e1aeca9a25b066e9010c376f0e618af59d1`,
tag `phase3-fit-v0.1`

Related data-contract plan:
[`MIGRATION_023_APPLICATION_OUTCOME_CONTRACT_PLAN.md`](MIGRATION_023_APPLICATION_OUTCOME_CONTRACT_PLAN.md)

## 1. Objective

Phase 4 turns the verified Phase 3 backend into a safely operated, minimally
usable product loop. It has two immediate workstreams:

1. production observability, incident response, and release safety for the
   existing Eligibility/Fit services;
2. a thin authenticated user experience from student data intake through
   Eligibility, six-dimensional Fit, Financial review, and privacy deletion.

Application tracking and verified outcome collection join the product loop
only after the separately reviewed provisional Migration 023 contract is
implemented under separate authorization.

Phase 4 does not change the frozen meanings of Eligibility or Fit. It does not
implement Competitiveness, admission probability, ranking, recommendation, or
learned weights.

### 1.1 Confirmed gaps that drove Phase 4A-1

The frozen Phase 3 functions are behaviorally verified, but the Phase 4 review
confirmed operational hardening work that must precede browser rollout:

- all four functions currently use wildcard CORS;
- bounded adapter failures currently return internal `error.message` and
  `error.detail` values to the caller;
- there is no shared server-generated request ID or closed public error
  catalog;
- content-type, body-size, deadline, and release-skew handling is repeated or
  absent rather than governed by one shared boundary.

These findings do not change the Phase 3 semantic result contract. Phase 4A-1
closed the shared request ID, CORS, content-type/body-size, error-redaction,
release-identity, and cooperative deadline boundaries and re-ran the
established remote smoke. The request and dependency deadlines propagate an
abort signal into the actual database network request; the wrapper does not
race the whole handler and return while an uncancelled finalizer continues.
Their exact disposition is recorded in
[`PHASE_4A1_EDGE_HTTP_BOUNDARY_RELEASE.md`](PHASE_4A1_EDGE_HTTP_BOUNDARY_RELEASE.md).

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
- a closed public error catalog; raw exception messages, PostgREST details,
  hints, SQLSTATE text, and nested causes never cross the response boundary;
- explicit JSON content-type and bounded request-body enforcement;
- an environment-configured browser-origin allowlist with exact preflight and
  response behavior; wildcard CORS is forbidden in production;
- automatic redaction before an event leaves the process.

The first observability implementation is service-level. Migration 019 is the
Profile backend core, Migration 020 is the Frozen Profile to new DRAFT fork,
Migration 021 is the hosted Auth subject compatibility repair, and Migration
022 is the owner-scoped Profile taxonomy projection. The Application/Outcome
plan now has a provisional future Migration 023 identity. Taxonomy 022 remains
uncommitted, paused, and not baseline-ready;
that number remains provisional until implementation authorization. Any
durable database operation receipt or trace table requires a separate additive
migration after the implemented Application/Outcome migration.

#### Phase 4A-1 bounded implementation increment

**Completion:** separately authorized, implemented, deployed, and remotely
verified at code build
`099a348e6b2ea9dc757efa2faacc675ba673ad5d`. The implementation
release-record baseline remains
`27d58545c5573f92051a31071bf345bf4d2446e2`; the final Phase 4A-1 release
baseline is the docs-only commit named by annotated tag
`phase4a1-edge-http-v1-final`. No further Phase 4 increment is authorized by
that completion or freeze.

The completed first mutation set was limited to:

- one new shared Edge HTTP-boundary module and its pure unit/adversarial tests;
- refactoring the four existing function `index.ts` files to use that module;
- deployment configuration for allowed browser origins and release identity;
- redeployment and anonymous/authenticated smoke of those four functions.

It does not edit the generated Fit runtime bundle, Fit/Eligibility packages,
database migrations, evaluator identity, result payloads, or SQL contracts.

Browser-origin behavior is exact:

- the server generates the request ID; an untrusted inbound request ID is not
  adopted as the authoritative trace identity;
- an allowlisted Origin receives that exact origin plus `Vary: Origin`;
- an unknown browser Origin receives no CORS grant and its preflight is
  rejected;
- a non-browser request without Origin may proceed through normal
  authentication but receives no wildcard CORS header;
- `x-request-id` is exposed explicitly; credentials/cookies are not enabled.

Success responses remain semantic/schema compatible; existing fields, values,
nullability, enum semantics, and HTTP status behavior are unchanged. Exact JSON
serialization byte equivalence is not required. Failure bodies that reach the
shared function boundary use a closed `{error, requestId}` envelope with an
optional catalog-authored public message; no raw adapter/database text is
returned.

Known non-blocking platform boundary exception: with `verify_jwt=true`,
Supabase may reject a credential-free request before the Edge Function runs.
That gateway-owned response does not contain the shared server-generated
request ID. Changing the platform JWT boundary or adding an outer proxy was not
part of Phase 4A-1.

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

The executable-source/capability review and the refined metric, alert,
retention/access, canary, and rollback contract are recorded in
[`PHASE_4A2_OBSERVABILITY_CANARY_PLAN.md`](PHASE_4A2_OBSERVABILITY_CANARY_PLAN.md).
The subsequent authenticated, GET-only plan/RBAC/field discovery and manual
historical canary are recorded in
[`PHASE_4A21_NATIVE_READ_ONLY_CANARY_REVIEW.md`](PHASE_4A21_NATIVE_READ_ONLY_CANARY_REVIEW.md).
The review confirmed a Free plan, one-day native log retention, no narrow
read-only role, four ACTIVE version-9 functions, and 40/40 application events
matching the frozen release/event contract. These records distinguish signals
available from the current closed Edge event, count-only database gauges, and
signals that do not yet have a truthful source. They do not authorize a
dashboard, scheduled query, alert, synthetic request, deployment, log drain,
or migration.

Free-plan logging/Metrics limits, missing warm-latency evidence, monitoring
role limitations, synthetic-canary prerequisites, and dashboard/alert gaps
are Phase 4A-2 readiness findings only. They do not block or reopen the Phase
4A-1 freeze and are not addressed by its final docs-only commit.

Initial dashboards must expose aggregates only:

- request count, success rate, and latency percentiles by endpoint/release;
- 401, 403/404, 409, 422, and 5xx counts by stable error code;
- Fit evaluations started, completed, failed closed, and left `BUILDING`;
- Financial normalizations prepared, verified, retired, resumed at the Edge
  endpoint, and left `DRAFT`; review-request rejection is not a persisted
  Financial lifecycle state;
- committed privacy-deletion tombstones; attempts and integrity failures only
  after a separately authorized privacy-safe operational source exists;
- deployment version skew between the four Edge Functions;
- database connection/RPC failure rate and retry behavior.

Immediate paging conditions:

- any privacy-deletion integrity failure, once a truthful privacy-safe source
  exists (not executable from the current event/schema);
- any deployed function missing its expected build identity;
- sustained 5xx rate above 1% with at least five requests in five minutes;
- a release producing three consecutive internal failures during canary smoke;
- any completed evaluation with a missing or malformed fingerprint.

Operational review conditions:

- a `BUILDING` evaluation older than 15 minutes;
- a Financial normalization left `DRAFT` for more than 72 hours;
- repeated authorization failures by a future approved bounded client-class
  enum; no current user/IP/token-derived grouping is permitted;
- p95 latency regression greater than 50% against the preceding verified
  release baseline.

Numeric service-level objectives are ratified only after a seven-day clean
baseline. The initial proposed availability objective is 99.5%, excluding
caller-caused 4xx responses and planned maintenance.

### 3.3 Retention and access

- raw runtime events: shortest operationally useful retention, with 14 days as
  the policy ceiling only if the active hosted plan exposes a compatible
  control; otherwise the plan-controlled retention is an explicit privacy
  review gate and must not be described as configured;
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
→ optionally create an application record after provisional Migration 023
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
10. Application tracker and outcome reporting only after provisional Migration 023.

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
- return only a bounded public message selected from the stable error catalog,
  never `error.message` or `error.detail` from adapter/database exceptions;
- avoid placing the service-role credential in the browser.

New API surface is grouped by capability rather than one endpoint per table:

- profile draft/freeze orchestration;
- intent draft/freeze orchestration;
- Eligibility v0.2 evaluation orchestration;
- the existing Fit and Financial endpoints;
- privacy export/deletion orchestration;
- Application/Outcome commands after provisional Migration 023.

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

- Migration 023 receives independent design approval and implementation
  authorization;
- clean `001→023`, populated `022→023`, RLS, concurrency, privacy, and remote
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

This document records the Phase 4 plan and the completion state of the
separately authorized Phase 4A-1 increment. It does not authorize any further
code, infrastructure, dashboard, UI, migration, storage, monitoring vendor, or
production rollout changes. Each subsequent implementation increment starts
only after its scope and mutation authority are separately approved.
