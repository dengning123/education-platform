# Phase 4A-2.1 Native Read-Only Canary Review

Status: **EXECUTED — HISTORICAL READ-ONLY CANARY PASSED; AUTOMATION NOT AUTHORIZED**

Date: 2026-08-22

Application release floor: annotated tag `phase4a1-edge-http-v1`, commit
`27d58545c5573f92051a31071bf345bf4d2446e2`

Expected Phase 4A-1 source build:
`099a348e6b2ea9dc757efa2faacc675ba673ad5d`

Related plan:
[`PHASE_4A2_OBSERVABILITY_CANARY_PLAN.md`](PHASE_4A2_OBSERVABILITY_CANARY_PLAN.md)

## 1. Scope and decision

The newly authorized Phase 4A-2.1 increment was executed through remote,
read-only Supabase Management API requests. It mechanically confirmed the
hosted plan and RBAC surface, discovered the actual log fields, reviewed
bounded aggregate queries, and ran one historical-window manual canary.

The canary passed its read-only contract checks. This does **not** authorize a
dashboard, scheduled reader, alert, log drain, durable aggregate store,
third-party monitoring connection, synthetic business request, Auth user,
database write, Edge deployment, secret/configuration change, migration, UI,
Migration 019, or Competitiveness implementation.

No raw log row, request/response body, header value, IP address, user claim,
email/name, object UUID, evidence, Fit/Eligibility result, financial amount,
database error text, access token, API key, or cookie was printed, exported,
or written to the repository.

## 2. Authenticated read-only execution path

The following GET-only paths were exercised:

- `/v1/projects`;
- `/v1/organizations/{slug}`;
- `/v1/profile`;
- `/v1/organizations/{slug}/members`;
- `/v2/organizations/{slug}/roles`;
- `/v1/projects/{ref}/functions`;
- `/v1/projects/{ref}/analytics/endpoints/logs`.

The repository-recorded CLI line is `2.115.0`. The published stable CLI could
read project/function metadata but did not expose the new generic Management
API command. The official `v2.115.0` source at commit
`18ae43a34a2257458197b62f74e2a97e2b5cf7f9` did expose that GET path and reused
the existing CLI login state.

One official-client defect was confirmed: the generated logs response schema
rejects the hosted API's successful `error: null` response, producing a local
`SchemaError` even though the HTTP response is 200. The log canary therefore
used the same official CLI keyring account/fallback policy in one transient
process and called the current GET endpoint directly. The token existed only
in process memory, was never printed or persisted, and was cleared before the
sanitized report was emitted. This workaround changed no remote or repository
state.

## 3. Hosted plan and RBAC findings

| Check | Confirmed result | Consequence |
| --- | --- | --- |
| Hosted plan | `free` | Current advertised raw log retention is one day; the Metrics endpoint and log drains are not included. |
| Current member role | `Owner` | Sufficient for this one-off inspection but too broad for a scheduled monitoring reader. |
| Current member MFA | Disabled | Security finding for the human owner account; no account setting was changed. |
| Available organization roles | `owner`, `administrator`, `developer` | No Read-Only or project-scoped operations role is available on this plan. |
| Fine-grained scheduled reader | Not provisioned | Phase 4A-2.2 remains blocked; the owner personal token must not become an automation credential. |
| Seven-day native baseline | Unsupported on current retention | A seven-day SLO baseline cannot be claimed without a plan/capability change or separately authorized aggregate retention. |

## 4. Actual log schema discovery

The bounded discovery window was `2026-08-22T02:26:00Z` through
`2026-08-23T02:16:00Z` (23 hours 50 minutes).

| Source | Rows in window | Confirmed structure |
| --- | ---: | --- |
| `function_logs` | 183 | `event_message`, `source`, and `log_attributes`; 40 rows were exact `FIT_EDGE_REQUEST_V2` JSON events. Platform attributes include deployment/function/execution/request identifiers, runtime version, region, level, memory/CPU, boot time, and reason. |
| `function_edge_logs` | 148 | Fixed-path/method/status and execution-time attributes exist, but the same map also contains request URL, IP/header values, geographic/network metadata, Auth user, and JWT subject/session/signature metadata. |

The 40 application events had exactly these 12 JSON keys, each present 40
times and with no thirteenth key:

`boundaryVersion`, `coldStart`, `deployedBuild`, `durationMs`, `endpoint`,
`errorCode`, `event`, `requestId`, `semanticRelease`, `stage`, `status`, and
`statusClass`.

Consequences:

- the application event is safe for the approved closed-field aggregates;
- `requestId` remains incident lookup material and is never selected or
  grouped in aggregate monitoring;
- raw `function_edge_logs`, `log_attributes`, headers, URLs, claims, and raw
  Function Invocations are prohibited monitoring outputs;
- steady-state queries may use the four fixed function path suffixes only as
  a filter and must emit the closed endpoint code rather than the path;
- the one-off `mapKeys(log_attributes)` discovery query is not a scheduled
  metric query.

## 5. Reviewed aggregate-query contract

Every approved log query uses the current `logs` endpoint, fixes one source,
passes explicit UTC `iso_timestamp_start` and `iso_timestamp_end` parameters,
keeps the interval at or below 24 hours, and returns bounded aggregates only.
The deprecated `logs.all` endpoint is forbidden.

### 5.1 Application event aggregate

```sql
select
  JSONExtractString(event_message, 'endpoint') as endpoint,
  JSONExtractString(event_message, 'semanticRelease') as semantic_release,
  JSONExtractString(event_message, 'deployedBuild') as deployed_build,
  JSONExtractString(event_message, 'boundaryVersion') as boundary_version,
  JSONExtractString(event_message, 'stage') as stage,
  JSONExtractUInt(event_message, 'status') as status,
  JSONExtractString(event_message, 'statusClass') as status_class,
  if(
    JSONExtractRaw(event_message, 'errorCode') = 'null',
    'NONE',
    JSONExtractString(event_message, 'errorCode')
  ) as error_code,
  JSONExtractBool(event_message, 'coldStart') as cold_start,
  count() as event_count,
  min(JSONExtractUInt(event_message, 'durationMs')) as min_duration_ms,
  quantileExact(0.5)(JSONExtractUInt(event_message, 'durationMs')) as p50_duration_ms,
  quantileExact(0.95)(JSONExtractUInt(event_message, 'durationMs')) as p95_duration_ms,
  max(JSONExtractUInt(event_message, 'durationMs')) as max_duration_ms
from logs
where source = 'function_logs'
  and JSONExtractString(event_message, 'event') = 'FIT_EDGE_REQUEST_V2'
group by
  endpoint, semantic_release, deployed_build, boundary_version, stage,
  status, status_class, error_code, cold_start
order by endpoint, status, error_code, cold_start
limit 200
```

This query never selects `event_message` or `requestId`. Before a result is
accepted, endpoint/release/build/boundary/stage/status/error values must be
validated against their closed catalogs; an unknown value fails the canary
rather than becoming a new dimension.

### 5.2 Contract-count guard

The companion count-only guard verifies, for every selected application
event:

- exactly 12 JSON keys and a v4 UUID `requestId`;
- one of the four endpoint codes;
- `fit-v0.1`, the expected Phase 4A-1 build, `fit-edge-http-v1`, and
  `RESPONSE`;
- status `100..599` with the matching status class;
- duration `0..600000`;
- `errorCode` is null or belongs to the closed public catalog.

It returns only `event_count` and one matching count per invariant. Passing
requires every matching count to equal `event_count`; no sampled raw value is
permitted.

### 5.3 Gateway aggregate

```sql
select
  multiIf(
    endsWith(toString(log_attributes['request.pathname']), '/fit-evaluate'),
      'FIT_EVALUATE',
    endsWith(toString(log_attributes['request.pathname']), '/fit-normalization-prepare'),
      'FIT_NORMALIZATION_PREPARE',
    endsWith(toString(log_attributes['request.pathname']), '/fit-normalization-review'),
      'FIT_NORMALIZATION_REVIEW',
    endsWith(toString(log_attributes['request.pathname']), '/fit-normalization-resume'),
      'FIT_NORMALIZATION_RESUME',
    'OTHER'
  ) as endpoint,
  toString(log_attributes['request.method']) as method,
  toUInt16OrZero(toString(log_attributes['response.status_code'])) as status,
  count() as event_count
from logs
where source = 'function_edge_logs'
  and (
    endsWith(toString(log_attributes['request.pathname']), '/fit-evaluate')
    or endsWith(toString(log_attributes['request.pathname']), '/fit-normalization-prepare')
    or endsWith(toString(log_attributes['request.pathname']), '/fit-normalization-review')
    or endsWith(toString(log_attributes['request.pathname']), '/fit-normalization-resume')
  )
group by endpoint, method, status
order by endpoint, method, status
limit 200
```

The fixed pathname is filter-only. The query never returns the path, URL,
request ID, IP, header, Auth user, JWT field, body, or other attribute value.
`OTHER` is a canary failure and may not become a retained dimension.

## 6. Manual historical canary result

### 6.1 Deployment identity

All four intended functions were returned by the Management API as `ACTIVE`,
version `9`, with `verify_jwt=true`:

- `fit-evaluate`;
- `fit-normalization-prepare`;
- `fit-normalization-review`;
- `fit-normalization-resume`.

### 6.2 Application-event contract

All 40 `FIT_EDGE_REQUEST_V2` rows passed every count-only guard:

- 40/40 exact 12-key schema;
- 40/40 valid request-ID shape without selecting an ID;
- 40/40 expected endpoint, semantic release, deployed build, boundary
  version, and stage;
- 40/40 valid status/status-class, closed error-code, and duration bounds.

Endpoint coverage was `FIT_EVALUATE=28`,
`FIT_NORMALIZATION_PREPARE=3`, `FIT_NORMALIZATION_REVIEW=6`, and
`FIT_NORMALIZATION_RESUME=3`. The observed window contained 22 2xx responses,
18 closed 4xx responses, and no 5xx or deadline-class response. Observed
durations were bounded; the maximum was 13,485 ms.

All 40 application events reported `coldStart=true`. Therefore this window
does not provide a warm-latency comparison and cannot ratify a cold-start
threshold.

### 6.3 Gateway boundary

The gateway aggregate contained 148 invocations for only the four fixed
function paths. It contained 85 status-401 responses, distributed across all
four functions. No application event had status 401, confirming the known
platform boundary in which `verify_jwt=true` can reject a request before the
shared handler emits its request ID/event.

The broad historical window was not a controlled request cohort. The numeric
difference between gateway invocations and application events is therefore a
coverage signal only and is not attributed to a user, request, or failure
cause.

## 7. Decision and remaining blockers

**PHASE 4A-2.1 HISTORICAL READ-ONLY CANARY PASSED.**

The current application release identity and closed operational event are
observable through bounded native aggregates. No application, database, or
platform mutation was required.

Phase 4A-2.2 remains unauthorized and mechanically blocked by:

1. Free-plan one-day log retention, which cannot supply a native seven-day
   baseline;
2. absence of a Read-Only/project-scoped role on the current plan;
3. absence of the Metrics endpoint on the current plan;
4. no approved least-privilege automation credential, execution surface,
   notification owner/destination, or aggregate-retention mechanism;
5. no truthful privacy-deletion attempt/integrity-failure signal;
6. no warm sample in the retained application-event window.

These are Phase 4A-2 readiness findings only. They do not block or reopen the
Phase 4A-1 release, and the Phase 4A-1 final docs-only freeze does not attempt
to resolve them.

The manual Stage 0 historical canary is complete. Synthetic Stage 1, a
seven-day silent baseline, scheduled queries, alerts, dashboards, exports,
and any plan/account change require separate authorization.
