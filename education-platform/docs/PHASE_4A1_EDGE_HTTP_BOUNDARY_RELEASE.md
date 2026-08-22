# Phase 4A-1 Edge HTTP Boundary Release

Status: **IMPLEMENTED, DEPLOYED, AND REMOTELY VERIFIED**

Date: 2026-08-22

Source build: `4937ce0b4bf97f0de3190b0b202875f1b2198f12`

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
- a closed public error catalog that never returns adapter messages,
  PostgREST details, SQL text, hints, or nested causes;
- allowlisted operational events containing endpoint, release/build identity,
  stage, status class, stable error code, duration, and cold-start state only;
- refactored `fit-evaluate`, `fit-normalization-prepare`,
  `fit-normalization-review`, and `fit-normalization-resume` entrypoints with
  byte-compatible success JSON.

Production configuration is:

- `FIT_EDGE_ALLOWED_ORIGINS=none` because no browser UI is deployed;
- `FIT_EDGE_RELEASE_ID=phase4a1`;
- `FIT_EDGE_BUILD_HASH=4937ce0b4bf97f0de3190b0b202875f1b2198f12`.

The source implementation is in:

- `supabase/functions/_shared/http-boundary.js`;
- `supabase/functions/_shared/http-boundary.test.mjs`;
- the four existing function `index.ts` entrypoints;
- `supabase/functions/.env.example` and the shared boundary README.

## 2. Safe deadline disposition

The final review rejected an intermediate `Promise.race` timeout. The frozen
Fit runtime cannot cancel in-flight database work, so returning `504` while a
finalizer may still commit would make retries unsafe and could duplicate an
evaluation. Phase 4A-1 therefore does not pretend to provide operation
cancellation.

A hard application deadline remains a later observability/reliability
increment. It requires end-to-end abort propagation or a mechanically proven
idempotency receipt before it may alter responses. The platform's own runtime
limit remains unchanged.

## 3. Local verification

- shared HTTP boundary: 16/16 pure unit and adversarial tests passed;
- all four Edge entrypoints bundled successfully;
- Fit Engine: 14/14 tests passed;
- Fit adapter: 8/8 tests passed;
- Eligibility v0.1/v0.2: 12/12 tests passed;
- Eligibility v0.2 generated-registry drift check passed;
- migrations `001`–`018` are byte-unchanged by this increment;
- generated `supabase/functions/_shared/fit-runtime.js` is unchanged with
  SHA-256
  `0c6344b98b93ea38282236ac437bd8bc71eec3804bc103d7b09ad6ef790fd5b1`.

The boundary attack suite covers trusted/request-supplied request IDs,
allowlisted and denied origins, preflight methods/headers, non-browser
requests, authentication, method and media-type rejection, malformed or
oversized JSON, raw exception redaction, structured-log field allowlisting,
invalid deployment configuration, and deny-all production origin behavior.

## 4. Remote deployment and smoke

Project `lmcqotzbaoetnxceriwq` has all four functions ACTIVE at version 5 with
JWT verification enabled. Remote configuration names and digests were read
back without revealing values.

The final source-build smoke verified:

- all four credential-free requests were rejected with HTTP 401;
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
- every exercised Edge failure body contained only stable `error` and
  server-generated `requestId` fields.

The smoke read API keys and held passwords, access tokens, and temporary UUIDs
inside one process only. None were printed or written to files.

## 5. Cleanup and immutable smoke provenance

Final count-only audits confirmed:

- temporary Auth users: zero;
- active Phase 4A-1 student/profile rows: zero;
- active Phase 4A-1 evaluation rows: zero;
- active Phase 4A-1 smoke costs: zero;
- golden program version still active: exactly one.

Four disposable cost records are retired historical provenance. Three came
from diagnostic smoke attempts that progressed far enough to create a valid
isolated catalog fixture before a later assertion failed; the fourth is the
final passing smoke. Their immutable evidence and observations remain by
design, but no retired record is admissible to a new Fit evaluation.

## 6. Exclusions and next authorization boundary

This release did not modify migrations `001`–`018`, the generated Fit runtime,
Fit/Eligibility packages or semantics, evaluator identity, result schemas,
UI, Migration 019, Application/Outcome runtime, or Competitiveness.

Phase 4A-1 is complete. Dashboards/alerts, durable telemetry, cancellable
deadlines, the minimum product UI, Migration 019, and Competitiveness remain
separate future increments requiring explicit authorization.
