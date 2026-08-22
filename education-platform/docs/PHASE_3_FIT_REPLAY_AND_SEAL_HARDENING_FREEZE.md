# Phase 3 Fit Replay and Seal Hardening — FROZEN (Migration 015)

Status: **FROZEN**  
Migration: **`202608200015_fit_replay_and_seal_hardening.sql`**  
Milestone: **Fit Replay and Seal Hardening**  
Upstream freeze: **Migration 014 Financial Billing Basis Hardening**  
Freeze date: **2026-08-21**  
Next phase: **Fit Engine v0.1 implementation authorized**

This record freezes Migration 015 as an additive replay-integrity layer over
migrations `001`–`014`. It does not change Eligibility semantics, add Fit
scores or weights, implement Competitiveness, register an evaluator build, or
freeze Phase 3 overall.

The authoritative freeze set is:

1. `supabase/migrations/202608200015_fit_replay_and_seal_hardening.sql`
   (`sha256:f28572ee2a1b49fbf20b440625bbd73dd9796f650e37588b3d39b49c33acd607`);
2. `supabase/tests/007_phase015_fit_replay_and_seal_hardening.sql`
   (`sha256:c5052470fe6945a54f255b6980edeb3e588d35b2081015752301fddd670f5320`);
3. `supabase/tests/_phase015_concurrency_probe.sql`
   (`sha256:a10b5c7bacdce8c4075d991d13db091b1a5eb5cdc3bc16f6bb29c32e6bc62b7d`);
4. `supabase/tests/_phase015_installer_role_stack_regression.sh`
   (`sha256:b090009aa9211a34243554a9016690f2fac01c103404f25f77dc3b9b185b3971`).

Migration 015 must not be edited, reordered, squashed, or patched in place.
Later changes require a new additive migration.

## Authorized hosted-runner compatibility amendment — 2026-08-22

The user authorized one bounded amendment after the actual linked Supabase
runner exposed a role-stack difference that the original local runner did not
model. Hosted execution can begin with `current_user = postgres` while
`session_user` is a temporary login role. The original executor-scoped
adoption update used a bare `RESET ROLE`, which returned to that temporary
login and denied the following `private` DDL.

Migration 015 now captures the effective installer role transaction-locally,
performs the same executor-scoped adoption update, resets to the session role,
and immediately restores and asserts the captured installer before any further
DDL. Restoration is session-scoped so the hosted runner retains the installer
when it writes migration history after the migration's explicit `COMMIT`.
The amendment changes no replay discriminator, validator, semantic pin,
decision/result fingerprint, finalization, Financial, or categorical Fit
semantics. Its pre-amendment hash was
`3b17bdd5c947fc0c9c8cc66416d39c84c73b5f224ad9badbb43f4f451e3cbaf7`;
the current authoritative hash is the one listed above.

## Frozen guarantees

1. New and safely adoptable unsealed `BUILDING` Fit evaluations use the
   persisted discriminator `FIT_REPLAY_SEAL_V015`. Already sealed or completed
   014 evaluations remain legacy-null and retain the exact 014 path.
2. Seal performs the complete frozen 014 live-authority and Financial
   validator before it persists one immutable semantic envelope containing the
   exact 014 decision payload and decision/result fingerprints.
3. Finalization of a v015 evaluation reads the immutable semantic pin and
   evaluation-owned output rows only. It does not re-read mutable upstream
   catalog, applicability, selection, normalization, or review authority.
4. The finalizer verifies the envelope hash, embedded decision/result
   fingerprints, candidate fingerprint, and current result hash before
   completing. Missing, corrupt, downgraded, or physically tampered state fails
   closed.
5. A legacy-null evaluation cannot coexist with a v015 semantic pin. Direct
   pin mutation and runtime-role table access are denied by an immutable
   trigger, forced RLS, ownership, and function-only grants.
6. Seal serializes under the established evaluation/live-authority lock order.
   Concurrent finalizers serialize on the evaluation row and replay the same
   pin; after seal they do not wait on mutable normalization authority.
7. Authorized student privacy deletion cascades through semantic pins and the
   complete v014 Financial evaluation graph. Ordinary typed-row, normalization,
   and review mutation remains prohibited.
8. The v014 `AVAILABLE_FUNDING`, billing-basis, typed-conversion, decision
   fingerprint, result fingerprint, and categorical Fit semantics are not
   replaced or weakened.
9. Temporary schema `CREATE` privilege needed for Supabase ownership transfer
   is revoked before commit. Runtime roles receive no new direct protected DML.

## Accepted validation baseline

The following gates passed on 2026-08-21:

- clean PostgreSQL 15 `001→015` compile and static contract audit: **PASS**;
- committed 014 behavior fixture followed by 015 behavior suite: **PASS**;
- semantic-pin and result physical-tamper rejection: **PASS**;
- post-seal normalization retirement followed by pin-only finalization:
  **PASS**;
- authorized privacy deletion with no v014/v015 Financial evaluation residue:
  **PASS**;
- evaluation-lock, normalization-lock, pin-only finalizer, and two-finalizer
  concurrency matrix: **PASS**;
- sealed `BUILDING` legacy 014 upgrade and finalization through the preserved
  014 branch: **PASS**;
- completed legacy 014 upgrade with discriminator, hashes, and absence of pin
  preserved: **PASS**;
- actual Supabase CLI 2.115.0 clean `001→015` runner path: **PASS**;
- actual Supabase CLI populated `014→015` migration-up path in the disposable
  runner project: **PASS**;
- actual Supabase behavior and concurrency suites: **PASS**;
- formal repository Supabase clean `001→015` with history exactly 15 rows and
  SQL tests `001`, `002`, and `007`: **PASS**;
- post-commit executor schema `CREATE` privileges on `public` and `private`:
  **absent**;
- PostgreSQL 15.19 and 17.11 dual-role-stack install regression with distinct
  `session_user` and database-owning `current_user`: **PASS**;
- post-amendment clean PostgreSQL 15.19 and 17.11 `001→017` migrations plus
  ordered SQL suites `001`–`009`: **PASS**;
- frozen Migration 014 and its four companion test/probe hashes:
  **byte-for-byte unchanged**.

The formal local database was not destructively rewound after its successful
clean `001→015` run. The populated `014→015` path was exercised in the
disposable Supabase project using the same migration bytes.

## Scope boundary and next milestone

Migration 015 changes replay timing and integrity, not Fit meaning. SQL remains
the final persistence authority; the future engine remains pure,
persistence-neutral, categorical, evidence-bounded, and independent of
Eligibility and Competitiveness.

Fit Engine v0.1 implementation is separately authorized against the frozen
`001`–`015` boundary and `PHASE_3_FIT_ENGINE_PLAN.md`. That authorization does
not include a production API, deployment, evaluator-build registration,
aggregate Fit score, ranking, probability, recommendation, or final Phase 3
tag.

Migration 015 Fit Replay and Seal Hardening is formally **FROZEN**.
