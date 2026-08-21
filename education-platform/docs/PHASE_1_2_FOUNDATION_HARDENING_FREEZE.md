# Phase 1/2 Foundation Hardening — FROZEN (Migration 012 / Gate 1)

Status: **FROZEN**  
Migration: **`202608200012_frozen_foundation_critical_hardening.sql`**  
Milestone: **Foundation Hardening / Gate 1**  
Upstream: **migrations `001`–`011`**  
Next authorized phase: **Migration 013 — Eligibility Correctness v0.2**  
Freeze date: **2026-08-20**  
Purpose: Record Migration 012 as the approved Foundation Hardening contract
over frozen migrations `001`–`011`, without authorizing Eligibility v0.2,
Phase 3 Financial hardening, or Fit Engine implementation.

This record freezes only the Foundation Hardening milestone implemented by
migration `012`. It does not freeze Eligibility v0.2, Phase 3 overall, or the
Fit engine. Migrations `001`–`011` remain unchanged historical artifacts.
Migration `012` must not be edited, reordered, squashed, or patched in place.

The authoritative sources for this freeze are:

1. [`PHASE_1_2_FOUNDATION_REMEDIATION_PLAN.md`](PHASE_1_2_FOUNDATION_REMEDIATION_PLAN.md),
   the 012-owned design contract (sections 9A and 18);
2. `supabase/migrations/202608200012_frozen_foundation_critical_hardening.sql`,
   the frozen executable hardening; and
3. `supabase/tests/004_phase012_foundation_hardening.sql`, the 012 regression
   and adversarial suite, together with the accepted Phase 1/2/3 SQL and
   eligibility-engine baseline recorded below.

## 1. Frozen guarantees

The following thirteen guarantees are frozen:

1. Runtime lifecycle authorization is function-mediated.
2. Executor roles are NOLOGIN / NOBYPASSRLS.
3. Runtime roles have no direct protected lifecycle DML.
4. Security-significant legacy GUCs do not grant authority.
5. Shared student lifecycle locking is established.
6. Source identity/revision history is immutable and current-head controlled.
7. New KNOWN observations require exact nine-part REVIEWED_APPLICABLE evidence scope.
8. LEGACY_UNASSERTED observations remain historical only and cannot be re-authorized.
9. Historical Phase 1/2/3 records remain compatible.
10. Eligibility v0.1 API and semantics remain historical and unchanged.
11. Privacy deletion closes all student-owned rows through migration 012.
12. Primary-school and derived-feature lifecycle hardening are active.
13. Migration 012 contains no Eligibility v0.2 or Phase 3 Financial semantics.

## 2. Frozen migration

- `202608200012_frozen_foundation_critical_hardening.sql`
  - additive Foundation Hardening over migrations `001`–`011`;
  - function-mediated authorization with `NOLOGIN` / `NOBYPASSRLS` executors;
  - revocation of runtime protected lifecycle DML;
  - neutralization of security-significant legacy GUCs as authority;
  - shared student lifecycle locking;
  - immutable source identity/revision history with current-head control;
  - exact nine-part `REVIEWED_APPLICABLE` authority for new `KNOWN`
    observations;
  - `LEGACY_UNASSERTED` historical-only treatment;
  - privacy deletion closure through 012 student-owned rows;
  - primary-school and derived-feature lifecycle hardening.

Upstream migrations `001`–`011` are unchanged by this freeze. Phase 2
Eligibility v0.1 remains frozen by
[`PHASE_2_FREEZE.md`](PHASE_2_FREEZE.md). The Phase 3 Fit v0.1 database
contract remains frozen by
[`PHASE_3_DATABASE_FREEZE.md`](PHASE_3_DATABASE_FREEZE.md). Migration 012
hardens foundation primitives used by those contracts; it does not rewrite
their product semantics.

## 3. Explicitly excluded scope

The following are not part of this freeze and are not authorized by it:

- Eligibility v0.2 domain snapshots, negative-authority tables, replay pins,
  projection/`ABSENT` semantics, projected `AT_LEAST` thresholds, taxonomy
  ordinal infrastructure, v0.2 fingerprints, or
  `finalize_eligibility_evaluation_v02`;
- Migration 013 implementation;
- Migration 014 / Phase 3 Financial `billing_basis` hardening;
- Fit Engine implementation, evaluator-build registration, API, score,
  ranking, probability, or recommendation systems;
- in-place patches to migration `012` semantics.

## 4. Accepted validation baseline

The established freeze-acceptance results are:

- clean migrations 001–012: **PASS**
- populated 001–011 → 012 upgrade: **PASS**
- Phase 1 SQL: **PASS**
- Phase 2 SQL: **PASS**
- Phase 3 SQL: **PASS**
- Phase 012 SQL: **PASS**
- eligibility-engine: **8/8 PASS**
- cross-evidence borrowing probe: **REJECTED as required**
- LEGACY_UNASSERTED re-bind probe: **REJECTED as required**
- migrations 001–011: **unchanged**
- no 013/014 objects

## 5. Known non-blocking cautions

These cautions are recorded separately. They are **not** frozen semantic
defects and do not reopen the 012 contract:

- legacy test 001 still contains broad WHEN OTHERS;
- 004 dblink fixtures may autocommit outside rollback;
- hosted Supabase JWT/GoTrue/PostgREST integration remains a production-release check;
- pg_temp remains on some non-entry-point helpers;
- limited service_role EXECUTE remains on non-DML validators/helpers.

Hosted JWT/GoTrue/PostgREST verification remains a production-release check.
It does not invalidate this freeze and does not authorize rewriting 012.

## 6. Post-freeze change policy

012 semantics cannot be patched in place. Further changes require a new
additive migration.

The following may proceed without a new migration only when they do not alter
persisted meaning or enforcement:

- documentation clarification;
- additive tests that prove already frozen behavior;
- query or index optimization with unchanged observable behavior.

The following require a new additive migration:

- changing executor-role, function-mediated authorization, direct-DML,
  GUC-authority, or trusted `search_path` primitives;
- changing student lifecycle lock identity or order;
- changing source identity/revision or current-head locking;
- changing evidence applicability, nine-part `REVIEWED_APPLICABLE` authority,
  or `LEGACY_UNASSERTED` historical-only treatment;
- changing privacy deletion closure, primary-school, or derived-feature
  hardening;
- changing Eligibility v0.1 API or semantics;
- introducing Eligibility v0.2 or Phase 3 Financial semantics.

013 is the next authorized phase. It must not redesign 012 primitives. If 013
needs a new semantic capability, it must be additive on top of the frozen
executor-role model, direct-DML policy, trusted `search_path` policy, student
lifecycle lock identity/order, source revision model, evidence applicability
model, and source/current-head locking model.

## 7. Freeze boundary and next authorized phase

Migration 012 Foundation Hardening / Gate 1 is formally **FROZEN**.

Next authorized phase: **Migration 013 — Eligibility Correctness v0.2**.

This freeze does not authorize Migration 014, Fit Engine implementation, or a
production-release claim.
