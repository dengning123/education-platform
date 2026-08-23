# Phase 4A-2 Native Observability, Canary, and Rollback Plan

Status: **PHASE 4A-2.1 READ-ONLY CANARY EXECUTED — AUTOMATION NOT AUTHORIZED**

Date: 2026-08-22

Application release floor: annotated tag `phase4a1-edge-http-v1`, commit
`27d58545c5573f92051a31071bf345bf4d2446e2`

Phase 4A-1 source build:
`099a348e6b2ea9dc757efa2faacc675ba673ad5d`

Post-release documentation baseline inspected:
`33911e14ba7f34e2d249f41e1694cbddb99a81a8`

Related records:

- [`PHASE_4_PRODUCTION_OBSERVABILITY_AND_MVP_PLAN.md`](PHASE_4_PRODUCTION_OBSERVABILITY_AND_MVP_PLAN.md)
- [`PHASE_4A1_EDGE_HTTP_BOUNDARY_RELEASE.md`](PHASE_4A1_EDGE_HTTP_BOUNDARY_RELEASE.md)
- [`PHASE_4A21_NATIVE_READ_ONLY_CANARY_REVIEW.md`](PHASE_4A21_NATIVE_READ_ONLY_CANARY_REVIEW.md)

## 1. Authorization boundary

This document refines Phase 4A-2 only. Its initial authorization was
planning/review-only. A subsequent explicit authorization allowed Phase
4A-2.1 to confirm the hosted plan/RBAC and actual log fields, review aggregate
queries, and execute one historical-window manual read-only canary. The exact
evidence is recorded in the Phase 4A-2.1 review linked above. The work did not:

- deploy or reconfigure an Edge Function, database, secret, log drain, or
  monitoring service;
- create a dashboard, alert, scheduled job, durable telemetry store, or
  database migration;
- modify migrations `001`–`018`, the frozen Fit runtime, evaluator identity,
  Eligibility/Fit/Financial semantics, or response schemas;
- start UI, Migration 020, Application/Outcome runtime, or Competitiveness;
- print, export, or persist production log rows, request/response bodies,
  headers, IPs, claims, object IDs, or student-linked records;
- run a synthetic request or database count gauge.

Every implementation increment below requires separate mutation authority.

## 2. Evidence and confirmed current state

### 2.1 Repository and release state

The repository and authenticated read-only review confirmed:

- `phase4a1-edge-http-v1` is an annotated tag and resolves to the declared
  release floor;
- the scoped tracked diff for migrations `001`–`018` and
  `supabase/functions/_shared/fit-runtime.js` is empty;
- the repository's recorded Supabase runner version for the Phase 3/4A-1
  release work is CLI `2.115.0`;
- an isolated CLI `2.115.0` execution path successfully reused the existing
  login state and queried the linked project through GET-only Management API
  paths;
- the hosted organization is on the Free plan, the current member is Owner,
  and the available roles are only owner, administrator, and developer;
- the four intended functions are ACTIVE at version 9 with `verify_jwt=true`;
- the current `logs` endpoint returned bounded aggregates from both
  `function_logs` and `function_edge_logs`;
- `supabase/config.toml` configures the local project and PostgreSQL 15 but has
  no observability, retention, or alert configuration.

The generated CLI logs response decoder rejects the hosted API's successful
`error: null` response. Phase 4A-2.1 used the same official CLI keyring policy
in a transient process and called the GET endpoint directly; no credential was
printed or persisted. This is a local tooling defect, not evidence of a
remote query failure.

### 2.2 The exact Phase 4A-1 operational event

Every request admitted to a deployed function handler attempts to emit one
`FIT_EDGE_REQUEST_V2` JSON event through `console.log`. Its closed 12-field
schema is:

| Field | Permitted use |
| --- | --- |
| `event` | Fixed event discriminator. |
| `requestId` | Short-lived incident correlation only; never a metric label, export key, or retained aggregate dimension. |
| `endpoint` | One of the four closed endpoint codes. |
| `semanticRelease` | Expected value `fit-v0.1`. |
| `deployedBuild` | Expected Phase 4A-1 source-build identity. |
| `boundaryVersion` | Expected value `fit-edge-http-v1`. |
| `stage` | Currently fixed to `RESPONSE`. |
| `status` | Bounded HTTP status. |
| `statusClass` | `2xx` through `5xx`. |
| `errorCode` | Closed public error code or `null`. |
| `durationMs` | Integer bounded to `0..600000`. |
| `coldStart` | Boolean. |

The four endpoint values are `FIT_EVALUATE`, `FIT_NORMALIZATION_PREPARE`,
`FIT_NORMALIZATION_REVIEW`, and `FIT_NORMALIZATION_RESUME`.

The event contains no request or response body, student/profile/evaluation/
normalization identifier, evidence, Fit/Eligibility result, or financial
amount. Those fields remain prohibited globally.

### 2.3 Native Supabase surfaces and current disposition

Current official Supabase documentation, checked on 2026-08-22, establishes
the following platform capabilities:

| Surface | What it can supply | Constraint for this project |
| --- | --- | --- |
| Logs Explorer / unified `logs` table | `function_logs` for the JSON application event; `function_edge_logs` for gateway/network request metadata; `postgres_logs` for database logs. | Query one source at a time. Structured keys must be discovered, not guessed. Never select/export bodies, headers, free text, object IDs, or raw database errors for aggregate monitoring. |
| Management API `GET /v1/projects/{ref}/analytics/endpoints/logs` | Read-only ClickHouse SQL over the unified log stream. | Requires `analytics_logs_read`; a query window is at most 24 hours. The deprecated `logs.all` endpoint is forbidden in new work. |
| Function combined statistics endpoint | Platform function statistics for one `function_id` and interval. | Requires `analytics_usage_read`; exact response fields must be discovered before relying on them. |
| Metrics API | Prometheus-compatible PostgreSQL health/performance series for CPU, IO, WAL, connections, and query behavior. | Beta; names/labels may change. The endpoint is not included on the confirmed Free plan and remains unavailable for this phase. |
| Log drains | Export of platform log streams. | Not included on the confirmed Free plan and explicitly out of scope. No drain or third-party destination may be configured without separate approval and a redaction/cost review. |

Official references:

- [Supabase Logging](https://supabase.com/docs/guides/monitoring-and-debugging/logs)
- [Edge Function Logging](https://supabase.com/docs/guides/functions/logging)
- [Management API logs endpoint](https://supabase.com/docs/reference/api/usage)
- [Management API logs endpoint migration](https://supabase.com/changelog/48235-migration-of-supabase-management-api-logs-all-analytics-endpoint-to-logs-endpoint)
- [Metrics API](https://supabase.com/docs/guides/monitoring-and-debugging/metrics)
- [Access Control](https://supabase.com/docs/guides/platform/access-control)
- [Supabase plan comparison](https://supabase.com/pricing)

## 3. What can and cannot be measured now

### 3.1 Immediately derivable from `FIT_EDGE_REQUEST_V2`

Only aggregates over the closed event fields are allowed:

- request count by endpoint, semantic release, deployed build, boundary
  version, status/status class, stable error code, and cold-start boolean;
- 2xx, caller-caused 4xx, lifecycle-conflict 4xx, deadline, and 5xx rates;
- p50, p95, and p99 `durationMs` by endpoint and release identity;
- cold-start share and cold-start versus warm latency;
- presence of `configuration-unavailable` identity;
- mixed semantic release, build, or boundary-version values.

`requestId` is excluded from every aggregation and grouping. It is allowed
only for a time-bounded, single-incident lookup initiated from a client-visible
failure.

The event has no HTTP method field. Status 204 identifies the current allowed
preflight path, but a denied preflight cannot be separated from another denied
request solely by method. No metric may be labeled as an exact POST-request
count unless a later separately reviewed event version adds a bounded method
field.

### 3.2 Gateway measurements require `function_edge_logs`

With `verify_jwt=true`, a credential-free request can be rejected before the
Edge Function executes. It therefore produces no application request ID and
no `FIT_EDGE_REQUEST_V2` event. `function_edge_logs` is the preferred native
candidate for gateway 401 volume and total gateway invocations, but capture of
this pre-function rejection must be confirmed by bounded field discovery. If
that source and the function statistics endpoint do not expose it, the metric
remains blocked rather than inferred.

The two streams must not be joined by user, IP address, Authorization header,
or request body. Aggregate reconciliation is limited to function, fixed time
bucket, and status. A difference between gateway invocations and application
events is a coverage signal, not proof of a specific failure cause.

### 3.3 Database state needs count-only read queries

The application event has no business lifecycle transition. Current database
tables can support count-only hygiene gauges:

- Fit evaluations with `evaluation_state='BUILDING'` and `created_at` older
  than 15 minutes;
- completed Fit rows missing or carrying malformed candidate, decision, or
  result fingerprints;
- Eligibility evaluations with `evaluation_state='BUILDING'` older than 15
  minutes;
- completed Eligibility rows missing or carrying malformed input/result
  fingerprints, with v0.1/v0.2 columns handled by their frozen contracts;
- Financial review rows with `status='DRAFT'` and `created_at` older than 72
  hours;
- verified Financial reviews whose required immutable normalization/pin graph
  is incomplete, using an approved invariant query derived from the frozen
  014/015 contract.

These queries must return only aggregate counts and fixed state/version codes.
They must not return UUIDs, financial values, evidence, timestamps at row
granularity, or user-linked fields. Running or scheduling them is not
authorized by this plan.

### 3.4 Confirmed non-derivable signals

The umbrella Phase 4 plan listed signals that the current schema/event cannot
truthfully supply:

- Financial normalization has the persisted lifecycle
  `DRAFT → VERIFIED → RETIRED`; it has no persisted `REJECTED` state.
  Request-level review rejection can be counted by stable Edge error code,
  but it must not be presented as a persisted business transition.
- A successful `resume` request is observable at the Edge endpoint; there is
  no separate persisted resume audit event.
- The intentionally non-linkable deletion tombstone proves committed
  deletions but cannot reconstruct deletion attempts or associate a failure
  with a student. There is no current privacy-deletion Edge event or durable
  operation receipt.
- Raw Postgres error text is not an acceptable substitute for any missing
  application signal.

Privacy-deletion attempt/success/integrity-failure alerts remain blocked until
a separately authorized, privacy-safe source exists. Any durable receipt table
would require a new additive migration after Migration 021 under the existing
umbrella plan; this document does not authorize it.

## 4. Metric contract

### 4.1 Fixed dimensions

The only application dimensions are:

- five-minute UTC time bucket;
- closed endpoint code;
- semantic release;
- deployed build;
- boundary version;
- status, status class, and closed error code;
- cold-start boolean.

No user, network, geographic, request-ID, object-ID, header, payload, error
text, evidence, result, or financial dimension is allowed.

### 4.2 Initial aggregates

| Metric | Definition | Source |
| --- | --- | --- |
| Boundary responses | Count of `FIT_EDGE_REQUEST_V2` events, including current 204 preflight responses. | `function_logs` |
| Eligible boundary attempts | Boundary responses excluding current status 204. This is version-scoped because the current four POST handlers have no 204 success response. It includes denied preflight and is not an exact POST count. | `function_logs` |
| Service availability | `2xx / (2xx + 5xx + deadline-class responses)` over eligible boundary attempts. Caller-caused 4xx is excluded and reported separately. | `function_logs` |
| Closed failure rate | Count/rate by stable non-null `errorCode`. | `function_logs` |
| Internal failure rate | 5xx events divided by eligible boundary attempts. | `function_logs` |
| Deadline rate | `REQUEST_ABORTED`, `REQUEST_DEADLINE_EXCEEDED`, or `DEPENDENCY_DEADLINE_EXCEEDED` divided by eligible boundary attempts. | `function_logs` |
| Latency | p50/p95/p99 of bounded `durationMs` by endpoint and release. | `function_logs` |
| Cold-start share | `coldStart=true` divided by boundary responses; compare cold/warm latency. | `function_logs` |
| Identity skew | Count of any identity tuple other than the one authorized for the release. | `function_logs` plus function configuration read-back |
| Gateway response count | Count by function, fixed time bucket, and status; especially pre-function 401. | `function_edge_logs` |
| Event coverage | Gateway invocations minus application events within the same function/time bucket. Diagnostic only. | Both log sources, aggregated separately |
| Stale Fit/Eligibility/Financial work | Count-only gauges described in section 3.3. | Read-only SQL |
| Database saturation/health | Selected connection, CPU, IO, WAL, and query series after exact series discovery. | Metrics API |

The proposed 99.5% availability objective is not ratified until a complete
seven-day baseline exists. If the active plan retains less than seven days of
logs and no separately authorized aggregate store exists, the objective cannot
be mechanically baselined and remains provisional.

## 5. Alert plan

Alert thresholds are proposals, not active rules.

| Severity | Proposed condition | Minimum evidence | Response |
| --- | --- | --- | --- |
| P0 | Any privacy-deletion integrity failure. | A future authorized privacy-safe signal; current source absent. | Stop deletion rollout, preserve only permitted aggregate evidence, invoke privacy incident runbook. |
| P0 | Any completed evaluation failing the frozen fingerprint shape/completeness invariant. | Count-only SQL gauge equals at least 1. | Stop new evaluation traffic and investigate database integrity; do not log affected IDs globally. |
| P1 | Any deployed function is missing or differs from the expected semantic release/build/boundary tuple. | Configuration read-back and/or at least one skewed event. | Halt canary and restore Phase 4A-1 configuration/source floor. |
| P1 | Three consecutive internal failures during canary. | Three canary responses with closed internal 5xx codes. | End canary immediately; no automatic retry storm. |
| P1 | 5xx exceeds 1% with at least five 5xx responses in a rolling five-minute bucket. | Minimum-volume gate plus application-event counts. | Freeze rollout; correlate only by time bucket and short-lived request ID where necessary. |
| P1 | Stale `BUILDING` count is non-zero for two consecutive 15-minute checks. | Count-only database gauge. | Stop new starts for the affected evaluator and inspect transaction/finalizer health. |
| P2 | Financial `DRAFT` older than 72 hours. | Count-only database gauge. | Reviewer queue review; no paging outside business hours. |
| P2 | p95 latency increases more than 50% versus the preceding verified release baseline for three five-minute buckets. | At least 100 attempts per compared release or a later ratified volume floor. | Pause rollout and inspect cold-start/dependency/DB contributors. |
| P2 | Deadline-class rate exceeds 1% for three five-minute buckets. | At least 100 eligible boundary attempts. | Inspect dependency and database health; preserve idempotent retry rules. |
| P3 | Gateway/application event coverage gap changes materially. | Aggregated source counts; no user-level join. | Investigate gateway rejection or runtime logging loss during working hours. |

Authorization failures must not be grouped by IP, user, token, or client
fingerprint. Without an already approved bounded client-class enum in the
event schema, the umbrella plan's “one runtime/client class” alert is not
implementable and is deferred.

## 6. Retention, access, and cost plan

### 6.1 Hosted retention is plan-controlled

Supabase currently advertises API/database log retention of one day on Free,
seven days on Pro, 28 days on Team, and 90 days on Enterprise. It advertises
the Metrics endpoint on Pro/Team/Enterprise, not Free. These are time-sensitive
commercial capabilities and must be rechecked before implementation.

Phase 4A-2.1 mechanically confirmed that this organization is currently on
Free. Its operative native raw-log window is therefore one day and the Metrics
endpoint cannot be treated as available. No seven-day native SLO baseline may
be claimed on the current plan.

The repository's desired “no more than 14 days” raw-event retention cannot be
claimed as configured. If the active Supabase plan retains longer and offers
no project-level shortening control, implementation must either:

1. explicitly accept the hosted retention as a platform exception with
   privacy review; or
2. choose a separately authorized architecture that does not copy raw logs and
   retains only non-identifying aggregates.

Creating a log drain does not shorten the hosted copy and is not a retention
solution by itself.

### 6.2 Least privilege

- Human Logs Explorer access should use the narrowest available Supabase
  project role. Phase 4A-2.1 found only owner, administrator, and developer;
  the current member is Owner. No Read-Only or project-scoped operations role
  is available on the confirmed Free plan.
- Any future Management API reader must use a fine-grained token with only
  `analytics_logs_read`; function statistics may additionally require
  `analytics_usage_read`.
- Monitoring must never use an anon key, service-role key, database owner
  credential, or a broad personal token when a narrower credential exists.
- Metrics endpoint credentials must be held in a secret manager and never
  embedded in repository files, query text, dashboards, or logs.
- Access to raw Function Invocations is more sensitive because Supabase's
  dashboard can expose request/response data. It is not an approved monitoring
  source; operations views should use aggregate Logs Explorer queries.
- Query/download/export permission must not imply permission to export raw
  rows. CSV export of production logs is prohibited by this plan.

The observed Free-plan roles are too broad for a dedicated read-only
operations identity. That is a confirmed implementation gate, not a reason to
reuse the Owner personal token or weaken the policy.

### 6.3 Cost controls

- Every log query must select one source, include an explicit timestamp
  predicate, return aggregates only, and stay within a five-minute or at most
  24-hour window.
- Polling must apply jitter and backoff and remain below Management API rate
  limits.
- No full-retention scans, raw field maps, or unbounded cardinality groups.
- Log-ingest/query billing and any drain charges must be reviewed against the
  active plan before implementation.

## 7. Canary plan

### 7.1 Pre-canary gates

Before any Phase 4A-2 implementation can observe production:

1. re-verify the Phase 4A-1 tag, migration `001`–`018` hashes, frozen Fit
   runtime hash, evaluator/fingerprint identities, and four intended function
   bundle identities;
2. mechanically confirm the linked project's plan, raw-log retention,
   Metrics endpoint entitlement, available access roles, and audit capability;
3. discover the actual `function_logs` and `function_edge_logs` ClickHouse
   fields using a bounded, non-exporting query; never guess silent-empty map
   keys;
4. validate that a count-only query finds the exact expected release tuple and
   no unexpected identity value;
5. run the existing local telemetry/redaction adversarial suite;
6. approve exact query text, alert ownership, notification destination,
   credential scope, and rollback owner.

### 7.2 Native read-only canary stages

**Stage 0 — historical dry run**

- use only Supabase-native Logs Explorer or the read-only Management API;
- run aggregate queries over a bounded prior window;
- produce no alert, export, dashboard, drain, or stored dataset;
- compare log-derived counts with known Phase 4A-1 smoke outcomes without
  inspecting request bodies or object identifiers.

**Completion:** executed on 2026-08-22 over a 23-hour-50-minute window. The
read-only canary found 40 exact `FIT_EDGE_REQUEST_V2` events; every event
matched the 12-field contract and expected release/build/boundary tuple. It
also confirmed 148 gateway invocations, including 85 pre-function 401
responses, and four ACTIVE version-9 functions with JWT verification enabled.
See the Phase 4A-2.1 review for exact aggregate evidence and query text.

**Stage 1 — synthetic canary**

- confirm all four function source/configuration identities first;
- exercise authenticated no-Origin success, approved error-envelope cases,
  allowed/blocked preflight as applicable, and the separate gateway 401 path;
- query only aggregate counts for the exact canary time window;
- require one matching application event for every request that reached the
  function and no application event for the pre-function JWT rejection;
- require zero unexpected build/boundary values and zero forbidden event
  fields.

Temporary Auth and application data must use the established isolated-smoke
cleanup contract. A future run needs separate authorization because it mutates
remote Auth/application state.

**Stage 2 — seven-day silent baseline**

- no paging during baseline collection;
- review five-minute aggregates daily;
- ratify volume floors, p95 regression threshold, and availability objective
  only after seven complete days;
- if native retention is shorter than seven days, this stage is blocked until
  an approved aggregate-retention mechanism exists.

**Stage 3 — alert canary**

- enable notifications for one non-paging diagnostic rule first;
- inject only a synthetic, closed error condition that cannot alter semantic
  data;
- verify delivery, ownership, deduplication, and resolution;
- enable P1/P2 rules one at a time; P0 privacy paging remains blocked until a
  real privacy-safe signal exists.

No canary stage authorizes an Edge Function deployment or a business-semantic
change.

## 8. Rollback plan

Phase 4A-2 is intended to be monitoring-only. Its normal rollback is therefore
to disable the newly added reader/query schedule/alert configuration while
leaving application traffic and the four Phase 4A-1 functions untouched.

Rollback order for a future authorized increment:

1. disable alert delivery to stop notification storms;
2. stop the read-only polling/query job;
3. revoke the fine-grained monitoring token;
4. remove any newly authorized native query/dashboard configuration;
5. verify no log drain, durable raw copy, or unexpected credential remains;
6. re-run Phase 4A-1 function identity read-back and remote smoke;
7. record aggregate-only incident and rollback results.

The application rollback floor is `phase4a1-edge-http-v1`, not the older Phase
3 source. Rolling application code back to Phase 3 would remove the released
HTTP error, CORS, request-ID, deadline, and release-identity hardening and is
not a proportionate response to a monitoring failure. It is a separate
break-glass decision requiring explicit authorization and compatibility
review.

If a future canary unexpectedly changes function source/configuration, restore
all four functions as one compatibility set from the Phase 4A-1 release floor,
restore the production allowlist/release settings, confirm JWT verification,
and rerun the complete Phase 4A-1 remote smoke. Mixed function versions are a
failed rollback.

## 9. Implementation increments requiring new authorization

### Phase 4A-2.1 — native query contract and manual runbook

- mechanically confirm plan/roles/retention — **complete**;
- discover exact ClickHouse fields — **complete**;
- approve bounded aggregate log queries — **complete**; database count-only
  gauges were not run and remain future review work;
- execute a manual historical dry run — **complete**;
- execute a synthetic canary — **not authorized or executed**;
- create no dashboard, drain, durable store, or automatic alert.

### Phase 4A-2.2 — native scheduled aggregates and alerts

- choose the execution surface and alert destination;
- provision least-privilege credentials;
- implement seven-day silent baseline, alert ownership, and rollback;
- authorize any dashboard or scheduled resource explicitly.

### Optional later export

An external monitoring vendor or log drain is not selected. It requires a
separate privacy, residency, retention, cost, secret-management, and deletion
review and is outside Phase 4A-2.1.

## 10. Acceptance gates

A future Phase 4A-2 implementation is releasable only if all are true:

- every metric and alert has one truthful, named source;
- no metric relies on an unavailable business transition;
- all queries return aggregates only and exclude forbidden fields;
- request IDs never become dimensions or durable exported identifiers;
- gateway and application-event coverage are reported separately;
- exact release/build/boundary skew is detected;
- plan retention and role limitations are documented and accepted;
- seven-day baseline and volume gates are complete where required;
- canary alert delivery and rollback have been rehearsed;
- rollback leaves all four Phase 4A-1 functions on one verified identity set;
- migrations `001`–`018`, frozen runtime, semantic packages,
  evaluator/fingerprint identity, UI, Migration 021, and Competitiveness have
  no unauthorized diff.

## 11. Review decision and blockers

**PHASE 4A-2.1 HISTORICAL READ-ONLY CANARY PASSED — PHASE 4A-2.2 AND
SYNTHETIC CANARY REMAIN UNAUTHORIZED.**

Every limitation below is a Phase 4A-2 readiness finding. None is a Phase
4A-1 freeze blocker, none reopens the Phase 4A-1 implementation release, and
none is authorized for resolution by the Phase 4A-1 final docs-only freeze.

Phase 4A-2.1 resolved the project-tier and field-discovery questions:

- plan: Free; native raw-log retention: one day;
- roles: owner, administrator, developer only; current member: Owner;
- Metrics endpoint: not included on the confirmed plan;
- exact application event: 40/40 rows matched the closed 12-field contract;
- exact gateway aggregate fields: fixed path filter, method, and response
  status exist, while the surrounding attribute map contains prohibited
  network/header/JWT values and must never be exported raw.

Before any scheduled reader, dashboard, seven-day baseline, alert, or Phase
4A-2.2 work may start, the following remain blocked:

1. a least-privilege automation credential and execution identity;
2. an approved execution/notification surface and accountable owner;
3. an approved non-identifying aggregate-retention mechanism or compatible
   plan change for a seven-day baseline;
4. Metrics access if database telemetry remains part of the desired scope;
5. disposition of the missing privacy-deletion operational signal;
6. separate authorization for synthetic requests/Auth/application data and
   their cleanup contract;
7. warm-event evidence before cold-versus-warm latency thresholds are used.
