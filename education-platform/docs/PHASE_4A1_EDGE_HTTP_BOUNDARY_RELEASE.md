# Phase 4A-1 Edge HTTP Boundary Release

Status: **FINAL PHASE 4A-1 FREEZE APPROVED — IMPLEMENTED, DEPLOYED, AND
REMOTELY VERIFIED WITH ONE DOCUMENTED PLATFORM EXCEPTION**

Date: 2026-08-22

Code build identity: `099a348e6b2ea9dc757efa2faacc675ba673ad5d`

Implementation release-record baseline:
`27d58545c5573f92051a31071bf345bf4d2446e2`

Final docs-only freeze tag: `phase4a1-edge-http-v1-final`

The final tag resolves to the docs-only freeze commit. It does not replace or
reinterpret either the code build identity or the implementation
release-record baseline.

Phase 3 semantic baseline: tag `phase3-fit-v0.1`, commit
`55296e1aeca9a25b066e9010c376f0e618af59d1`

## 1. Released scope

Phase 4A-1 adds one shared non-semantic HTTP boundary used by the four existing
Fit Edge Functions:

- a server-generated UUID returned as `x-request-id` and in closed failure
  envelopes;
- an exact environment-backed browser-origin allowlist with no wildcard and
  no credential/cookie grant;
- strict `POST`/`OPTIONS`, JSON content type, and bounded request-body handling;
- a 50-second cooperative request deadline and 10-second per-dependency
  deadline, both propagated to the actual gateway `fetch` abort signal;
- a closed public error catalog that never returns adapter messages,
  PostgREST details, SQL text, hints, or nested causes;
- typed and defensively bounded operational events containing only endpoint,
  semantic release, deployed build, boundary version, stage, status class,
  stable error code, duration, and cold-start state;
- refactored `fit-evaluate`, `fit-normalization-prepare`,
  `fit-normalization-review`, and `fit-normalization-resume` entrypoints with
  semantically and schema-compatible success JSON.

Production configuration is:

- `FIT_EDGE_ALLOWED_ORIGINS=none` because no browser UI is deployed;
- `FIT_EDGE_SEMANTIC_RELEASE=fit-v0.1`;
- `FIT_EDGE_DEPLOYED_BUILD=099a348e6b2ea9dc757efa2faacc675ba673ad5d`;
- `FIT_EDGE_REQUEST_DEADLINE_MS=50000`;
- `FIT_EDGE_DEPENDENCY_DEADLINE_MS=10000`;
- code-owned `EDGE_HTTP_BOUNDARY_VERSION=fit-edge-http-v1`.

Remote configuration digests were compared mechanically with these exact
values. The older `FIT_EDGE_RELEASE_ID` and `FIT_EDGE_BUILD_HASH` settings
remain present but are not read by this boundary version.

The source implementation is in:

- `supabase/functions/_shared/http-boundary.js`;
- `supabase/functions/_shared/http-boundary.test.mjs`;
- the four existing function `index.ts` entrypoints;
- `supabase/functions/.env.example` and the shared boundary README.

## 2. Inspected executable path and deadline contract

The executable-path review started from the four deployed entrypoints, not a
planned wrapper path:

- `supabase/functions/fit-evaluate/index.ts`;
- `supabase/functions/fit-normalization-prepare/index.ts`;
- `supabase/functions/fit-normalization-review/index.ts`;
- `supabase/functions/fit-normalization-resume/index.ts`.

All four call the frozen `_shared/fit-runtime.js`. The corresponding source
gateway in `packages/fit-engine-adapter/src/database-gateway.ts` accepts an
injected `fetch` implementation as its fourth constructor argument. That real
extension point is now used by each entrypoint; the frozen runtime itself is
unchanged.

The executable inspection confirmed two pre-change defects: the shared
boundary had no request/dependency deadline, and operational events had only
generic release/build fields with no explicit semantic-release versus
deployed-build contract or boundary-version identity. Existing CORS, request
ID, body limit, public-error catalog, and success schemas were retained rather
than rewritten.

The implementation does not race the entire handler and return while an
uncancelled finalizer continues. It bounds body reads and propagates request
and dependency aborts into the actual database network request. The stable
closed deadline codes are `REQUEST_ABORTED`, `REQUEST_DEADLINE_EXCEEDED`, and
`DEPENDENCY_DEADLINE_EXCEEDED`. As with any aborted database network request,
callers must still respect the existing finalization/idempotency contract when
the server-side commit outcome is ambiguous.

## 3. Local verification

- shared HTTP boundary: 21/21 pure unit and adversarial tests passed;
- all four Edge entrypoints bundled successfully;
- Fit Engine: 14/14 tests passed;
- Fit adapter: 8/8 tests passed;
- Eligibility v0.1/v0.2: 12/12 tests passed;
- Eligibility v0.2 generated-registry drift check passed;
- migrations `001`–`018` are byte-unchanged by this increment;
- generated `supabase/functions/_shared/fit-runtime.js` is unchanged with
  SHA-256
  `0c6344b98b93ea38282236ac437bd8bc71eec3804bc103d7b09ad6ef790fd5b1`.

The boundary attack suite covers trusted/request-supplied request IDs and
invalid UUID generator output,
allowlisted and denied origins, preflight methods/headers, non-browser
requests, authentication, method and media-type rejection, malformed or
oversized JSON, raw exception redaction, structured-log field allowlisting,
invalid deployment configuration, stalled body reads, request abort,
dependency abort, and deny-all production origin behavior.

## 4. Remote deployment and smoke

Project `lmcqotzbaoetnxceriwq` has all four functions ACTIVE at final
configuration version 9 with JWT verification enabled. Version 8 is the source
deployment and version 9 reuses that source after restoring production Origin
configuration to `none`. Remote configuration names and digests were read back
without revealing values.

The version-8 source bundle digests are:

- `fit-evaluate`: `eaac9a9a44592152d4f58b2759941b8a598c88e0de8c665e8c8b63eb0ab64dce`;
- `fit-normalization-prepare`: `be9493f5b6db71ed6d9ee3df3bfe49f5059943b71b5fba6c8e01c46cfcf7d956`;
- `fit-normalization-review`: `bf437c5cfeea23e33459fd63f2adad53ec5769b0995f83d4d1213c7b6003ab07`;
- `fit-normalization-resume`: `743f248893351ae886ba3b0cabafab72ef48b5cf6fc5f1f3cdd8d5a4674cb963`.

The final source-build smoke verified:

- all four credential-free requests were rejected with HTTP 401 by the
  Supabase JWT gateway;
- a temporary exact Origin passed preflight and received that same exact
  `Access-Control-Allow-Origin` value plus `Vary: Origin`;
- an authenticated request with an unapproved browser Origin was rejected
  with HTTP 403 and no CORS grant;
- authenticated `fit-evaluate` completed with six categorical dimensions,
  sealed fingerprints, a server request ID, and no wildcard CORS header;
- Financial `prepare` created one DRAFT normalization;
- student self-review was rejected through the closed error envelope;
- an independently claimed reviewer completed review;
- `resume` completed the same evaluation with Financial
  `ALIGNMENT / MEDIUM / SUFFICIENT`;
- response scans found no score, weight, rank, probability, recommendation,
  Competitiveness, or Eligibility semantics;
- every exercised failure that reached the shared boundary contained only
  stable `error` and server-generated `requestId` fields;
- malformed JSON, unsupported media type, oversized body, blocked Origin, and
  independent-review rejection all had closed boundary envelopes;
- after restoring production `none`, browser preflight and actual browser
  Origin were denied while an authenticated no-Origin request still reached
  the boundary normally.

The smoke read API keys and held passwords, access tokens, and temporary UUIDs
inside one process only. None were printed or written to files.

## 5. Cleanup and immutable smoke provenance

Final count-only audits confirmed:

- temporary Auth users: zero;
- active Phase 4A-1 student/profile rows: zero;
- active Phase 4A-1 evaluation rows: zero;
- active Phase 4A-1 smoke costs: zero;
- golden program version still active: exactly one.

This supplemental validation created three isolated cost records: two runs
progressed through a valid catalog fixture before a later smoke assertion
failed, and the third was the final passing run. All three are retired. Together
with the four records documented by the earlier Phase 4A-1 release pass, seven
disposable retired records remain as immutable provenance. No retired record
is admissible to a new Fit evaluation.

## 6. Exclusions and next authorization boundary

This release did not modify migrations `001`–`018`, the generated Fit runtime,
Fit/Eligibility packages or semantics, evaluator identity, result schemas,
UI, Migration 019, Application/Outcome runtime, or Competitiveness.

One external gateway finding remains: a credential-free request is rejected
before the function executes because `verify_jwt=true`. The platform response
uses `code`/`message` and has no shared-boundary request ID. Making that
pre-function response conform would require changing the platform JWT boundary
or adding an outer proxy. Neither was authorized, so JWT verification remains
enabled and this was not changed. The shared closed-envelope contract applies
to requests admitted to the function.

Phase 4A-1 is complete within its authorized application boundary. A later
GET-only native-observability readiness review confirmed the current hosted
plan/RBAC/log shape without changing code, deployment, configuration, data, or
traffic. Its Free-plan log retention and Metrics limitations, absence of a
narrow monitoring role, lack of warm-latency evidence, synthetic-canary
authorization boundary, and dashboard/alert limitations are exclusively
Phase 4A-2 readiness findings. They are not Phase 4A-1 freeze blockers, do not
reopen this release, and are not resolved by this freeze.

No dashboard, alert, scheduled reader, monitoring vendor, durable trace/audit
table, metrics warehouse, generalized tracing framework, synthetic traffic,
UI, Migration 019, or Competitiveness implementation is authorized or started
by this final freeze.

## 7. Final freeze verification

The final freeze-only audit reconfirmed:

- migrations `001`–`018` have no working-tree or post-Phase-3 byte drift;
- the recorded hashes for migrations `012`–`018` and the Migration 018 SQL
  test match exactly;
- the Fit Engine source hash remains
  `e32a3ed849633a216e84dd23afae5bd60f261333c55e4c5a3c0841f6b795564e`;
- the frozen runtime SHA-256 remains
  `0c6344b98b93ea38282236ac437bd8bc71eec3804bc103d7b09ad6ef790fd5b1`;
- Eligibility/Fit semantic packages, the controlled adapter at the Phase 4A-1
  code build, evaluator registration, and fingerprint identities have no
  drift;
- all four deployed functions remain ACTIVE at version 9 with
  `verify_jwt=true`;
- the freeze commit contains documentation only and preserves all code,
  migration, runtime, semantic, evaluator, fingerprint, response, and remote
  configuration identities.

**PHASE 4A-1 FROZEN — CODE BUILD AND IMPLEMENTATION RELEASE RECORD
PRESERVED.**
