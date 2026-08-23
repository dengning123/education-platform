# Phase 4 and Migration 020 Plan Review

Status: **PHASE 4A-1 RELEASED — MIGRATION 020 STILL REQUIRES EXPLICIT AUTHORIZATION**

Date: 2026-08-22

Reviewed baseline: `phase3-fit-v0.1`

Phase 4A-1 release/document baseline:
`27d58545c5573f92051a31071bf345bf4d2446e2`

Reviewed plans:

- Reviewed pre-implementation Phase 4 plan hash at commit `8ee34f5`:
  `809c548b913fa4bffcd28a486ca2a6d1c16716f892902ddd22f3977555d3bf00`
- Migration 020 plan hash:
  `c4508925045fa216331fafeaa6f58203bc860436b4e6b85999f003629b2009d5`

## 1. Review scope

The review checked the plans against the frozen migrations `001`–`018`, the
four deployed Edge Functions, the student ownership/privacy lifecycle,
Eligibility v0.2, Fit v0.1, Financial independent review, PostgreSQL role
compatibility, hosted default ACL behavior, and the future Competitiveness
exclusion.

No application code, Migration 020 SQL, test 012, deployment, or
Competitiveness implementation was created by this review.

## 2. Confirmed blockers and dispositions

### Edge error and CORS boundary — closed in plan

All four current Edge entrypoints use wildcard CORS and expose adapter
`error.message/detail` on bounded failures. The Phase 4 plan now makes the
first increment a shared HTTP boundary with an origin allowlist,
server-generated request ID, closed error catalog, body/content-type limits,
and redacted structured events. Success semantics remain unchanged.

### Cross-evaluation application snapshot — closed in plan

An application cannot pin an Eligibility evaluation while its Fit evaluation
names a different non-NULL display-only Eligibility context. The 020 plan now
requires that Fit context to be NULL or exactly the pinned Eligibility
evaluation.

### Cross-application snapshot pointer — closed in plan

`submission_snapshot_id` is governed by a composite
`(application_id, snapshot_id)` foreign key, preventing an application from
pointing to another application's otherwise valid snapshot.

### Draft abandonment and idempotency — closed in plan

Physical DRAFT deletion would remove its idempotency witness. The contract now
uses `DRAFT → CANCELLED`, persists `cancellation_request_id`, retains the
terminal row for safe retry, and scopes duplicate prevention to non-CANCELLED
applications. Physical deletion remains privacy-cascade-only.

### Reviewer read authority — closed in plan

Reviewers receive no table SELECT. Two bounded, claim-gated RPCs provide stable
pagination or one exact candidate while withholding student/profile identity,
actor IDs, Fit/Eligibility details, raw evidence, and storage paths.

### Evidence hash is not proof — closed in plan

The plan explicitly forbids treating a content hash as verified evidence.
`DOCUMENT_VERIFIED` and `SOURCE_VERIFIED` require a separately approved
ephemeral evidence-delivery or direct-source confirmation path. Without it,
only `PLAUSIBILITY_REVIEWED` is available.

### Hosted role/ACL compatibility — closed in plan

Migration 020 must reuse the PostgreSQL 15/16+ installer-role compatibility
and safe role restoration pattern, revoke temporary schema CREATE, preserve
platform default ACL rows byte-for-byte, and assert the exact expanded
authenticated-function whitelist.

## 3. Phase 4A disposition

The Phase 4A-1 boundary is mechanically narrow enough for separate
implementation authorization:

- add one shared Edge HTTP-boundary module and tests;
- refactor only the four existing Edge entrypoints;
- configure exact allowed origins and release identity;
- preserve success-response fields, values, nullability, enum semantics,
  status behavior, and all Fit/Financial semantics under a semantic/schema
  compatibility contract;
- deploy only after local tests and repeat the established remote smoke.

It does not require a database migration and does not authorize UI work,
Migration 020, or Competitiveness.

### 3.1 Subsequent implementation disposition

The user separately authorized exactly this increment. It is now implemented,
deployed, and remotely verified at source build
`099a348e6b2ea9dc757efa2faacc675ba673ad5d`, with final release/document
baseline `27d58545c5573f92051a31071bf345bf4d2446e2`; see
[`PHASE_4A1_EDGE_HTTP_BOUNDARY_RELEASE.md`](PHASE_4A1_EDGE_HTTP_BOUNDARY_RELEASE.md).
This completion does not authorize another Phase 4 increment.

Supabase `verify_jwt=true` remains an intentional non-blocking platform
boundary: a credential-free request can be rejected before the function runs,
so that gateway-owned response has no shared request ID. Phase 4A-1 did not
disable gateway JWT verification or add an outer proxy.

## 4. Migration 020 disposition

The architecture is coherent and the identified semantic blockers are closed
at plan level. SQL implementation is not yet authorized. Before implementation
approval, the following mechanical artifacts must still be reviewed:

- exact column types, nullability, composite FK declarations, and index
  predicates;
- exact canonical snapshot serialization and field order;
- complete typed function signatures and return types;
- exact lifecycle/review/consent transition tables as SQL checks/validators;
- complete current `close_student_owned_rows` body plus v020 additions;
- exact grants, owners, RLS policies, JWT claim parsing, and function whitelist;
- research-consent product/legal wording;
- the ephemeral evidence-delivery decision if verification above plausibility
  is required for the first release;
- clean/upgrade/dual-role/hosted-ACL/concurrency/privacy/remote test fixtures.

Migration 020 remains a reserved planning identity. No SQL file should be
created until those artifacts and explicit implementation authorization exist.

## 5. Review decision

**PHASE 4A-1 PLAN APPROVED FOR SEPARATE IMPLEMENTATION AUTHORIZATION.**

**MIGRATION 020 ARCHITECTURE PLAN REVIEWED — SQL IMPLEMENTATION NOT YET
AUTHORIZED.**

Competitiveness remains future architecture only.
