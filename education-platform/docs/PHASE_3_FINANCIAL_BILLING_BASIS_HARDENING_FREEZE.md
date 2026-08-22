# Phase 3 Financial Billing Basis Hardening — FROZEN (Migration 014)

Status: **FROZEN**  
Migration: **`202608200014_financial_billing_basis_hardening.sql`**  
Milestone: **Financial Billing Basis Hardening**  
Upstream freeze: **Migration 013 Eligibility Correctness v0.2**  
Freeze date: **2026-08-21**  
Next phase: **Migration 015 separately frozen; Fit Engine implementation authorized**

This record freezes Migration 014 as the approved Financial admissibility and
execution-integrity hardening layer over migrations `001`–`013`. It does not
freeze Phase 3 overall, start the Fit Engine, authorize Migration 015, or
authorize any score, ranking, probability, recommendation, or statistically
learned Competitiveness model.

The authoritative freeze set is:

1. [`PHASE_3_FINANCIAL_BILLING_BASIS_HARDENING_PLAN.md`](PHASE_3_FINANCIAL_BILLING_BASIS_HARDENING_PLAN.md),
   the implementation contract;
2. `supabase/migrations/202608200014_financial_billing_basis_hardening.sql`
   (`sha256:3828faf3f0d3b776575474cf2dc8f70dbedc134eef00baac5d3364dcbf028b53`);
3. `supabase/tests/006_phase014_financial_billing_basis_hardening.sql`
   (`sha256:8dc95fc23eef32cf53cbafd2aa42faa73b531e9c0198316535e7bc95e1d542bf`);
4. `supabase/tests/_phase014_concurrency_probe.sql`
   (`sha256:4bc10b9460fc4cf0556888ca87d2f08e19f8eac87b2756b669849e7f9fba4496`);
5. `supabase/tests/_phase014_legacy_fixture.sql`
   (`sha256:abc1d023a1185fa6eee5b5d0ce6e0d62c057751abd5f03231173b81c11e868d6`);
6. `supabase/tests/_phase014_legacy_compatible_assert.sql`
   (`sha256:53c1ab3d1a8e8af16270f1abbb688e788f4dffc02b343af0be80eff1c51301fe`).

Migration 014 must not be edited, reordered, squashed, or patched in place.
Later changes require a new additive migration.

## 1. Frozen guarantees

The following guarantees are frozen:

1. Financial amount and `billing_basis` are independent canonical
   observations with independent applicability and evaluation-scoped source
   pins. A populated amount never supplies basis authority.
2. The persisted discriminator is
   `FINANCIAL_BILLING_BASIS_V014`. Legacy-null completed evaluations remain on
   the exact v011 compatibility branch and are not relabeled or recomputed.
3. A new v014 directional deterministic Financial signal has exactly one
   admissibility witness: either a complete direct witness or exactly one
   complete verified normalization witness.
4. Financial normalization lifecycle is `DRAFT → VERIFIED → RETIRED`.
   Verification freezes the semantic payload; reverse, skip, direct-verified,
   and post-verification mutation paths fail closed.
5. Conversion authority is typed. Required inputs and factors have closed
   roles, units, operations, ordinals, evidence, and value/formula contracts.
   Arbitrary legacy JSON cannot authorize conversion.
6. `AVAILABLE_FUNDING` never acts as a cost ceiling. A net path requires a
   separate funding declaration and the exact
   `NET_OF_VERIFIED_FUNDING` target basis; gross paths reject funding
   substitution.
7. `UNKNOWN`, SQL null, `STALE`, `SOURCE_CONFLICT`, missing or non-applicable
   evidence, extra rows, and zero/multiple witnesses reject rather than
   infer.
8. Direct and normalized fingerprints contain the complete semantic graph and
   exclude generated UUIDs and other incidental identity. Equivalent semantic
   graphs hash identically; semantic mutation changes the hash.
9. Finalization recomputes live canonical selection, observation,
   applicability, evidence, cost, method, review, typed input/factor,
   constraint, manifest, and pin state under the global lock order. Persisted
   pins cannot mask pre-finalization authority replacement or retirement.
10. SQL validates admissibility and integrity only. It does not compute Fit
    direction, assessment, ceiling comparison, target amount, score, weight,
    rank, probability, or recommendation.
11. All new protected tables use forced RLS and function-mediated writes.
    Runtime roles have no direct protected DML; executor row-lock privileges
    do not authorize business updates.
12. The approved single-file dual-transaction boundary is preserved: enum
    labels commit before the object transaction uses them; the object phase is
    transactionally all-or-nothing.
13. Clean `001→014` and populated `013→014` upgrades are both supported.
    Incomplete legacy BUILDING rows fail migration preflight atomically and
    require authorized discard/rebuild.

## 2. Compatibility and test-version boundary

The frozen SQL suites are version-scoped:

- tests `001`–`005` run on a fresh `001→013` baseline;
- migration `014` is then applied;
- tests `001`, `002`, and `006` run at the `014` head;
- `006` with `phase014_commit_fixture=1`, followed by
  `_phase014_concurrency_probe.sql`, runs only on a disposable database.

Tests `004` and `005` intentionally reject leaked `014` objects because they
freeze the 012/013 boundaries. Test `003` uses the legacy Financial assembly
fixture at the 013 boundary; new assembly at the 014 head adopts the v014
witness contract and is covered by `006`. This version scoping is not a waiver
of old behavior: the complete `001`–`005` suite passed after the final 003/015
test separation and before 014 was applied.

Phase 015 assertions live only in
`supabase/tests/_phase015_fit_replay_and_seal_hardening.sql`. They are not part
of any 014 command.

## 3. Accepted validation baseline

The following gates passed on 2026-08-21:

- README `psql -v ON_ERROR_STOP=1 -f` execution model: **PASS**;
- single-file dual-transaction enum/object probe on PostgreSQL 15: **PASS**;
- single-file dual-transaction probe through Supabase CLI 2.115.0: **PASS**;
- fresh PostgreSQL 15 `001→013` compile: **PASS**;
- full version-scoped SQL tests `001`–`005`: **PASS**;
- formal clean PostgreSQL 15 `001→014` plus `006`: **PASS**;
- formal populated PostgreSQL 15 `013→014`, compatibility assertion, and
  `006`: **PASS**;
- normal and superuser physical-tamper paths in `006`: **PASS**;
- selection replacement, method retirement, normalization retirement,
  finalizer/finalizer, and seal/finalizer concurrency probes: **PASS**;
- actual formal-repository Supabase `db reset`: **PASS**, with migration
  history exactly `001`–`014` and no 015 semantic-pin object;
- formal Supabase head tests `001`, `002`, `006`, superuser tamper, and
  concurrency: **PASS**;
- Eligibility v0.1 baseline: **8/8 PASS**;
- Eligibility v0.2 release suite: **12/12 PASS** (including four additive
  v0.2 test cases);
- v0.2 registry generator and drift check: **PASS**;
- generated SQL/TypeScript parity corpus: **190 vectors PASS**;
- formal migrations `001`–`013` versus the validated isolation copy:
  **byte-for-byte identical**;
- Migration 014: no `TODO`, `FIXME`, or 015 object/reference;
- temporary PostgreSQL and Supabase test environments: **cleaned after use**.

The first test connection after each Supabase `db reset` may race the CLI's
asynchronous service-container replacement. Freeze validation required a
stable database container identity and two consecutive checks for all 14
migration-history rows and required 014 objects before running assertions.
This was an environment-readiness condition, not a migration failure.

## 4. Migration 015 post-freeze disposition

At the moment of this 014 freeze, the then-existing 015 draft was quarantined
with SHA-256
`af525e7b71aa79f65dad78c21602bcc54296475d65288a4a7860bec5e0f7e7bb`.
That historical quarantine did not alter 014. A later explicit authorization
allowed 015 to be independently rewritten, validated, activated, and frozen.
Its current authority is
[`PHASE_3_FIT_REPLAY_AND_SEAL_HARDENING_FREEZE.md`](PHASE_3_FIT_REPLAY_AND_SEAL_HARDENING_FREEZE.md).

## 5. Explicitly excluded scope

This freeze does not authorize:

- Migration 015 implementation, execution, review, or release;
- Fit Engine implementation or evaluator-build registration;
- Fit scores, weights, rankings, admission probabilities, or recommendations;
- statistical learning of Competitiveness feature effects;
- changing Eligibility rule semantics or Fit categorical preference and
  constraint semantics;
- hosted JWT, GoTrue, PostgREST, or production-deployment certification.

The future Competitiveness modeling direction recorded in
`PRODUCT_ARCHITECTURE.md` remains architecture-only and separately gated.

## 6. Post-freeze change policy

Migration 014 semantics cannot be patched in place. Documentation
clarifications and additive tests may proceed only when they do not alter
persisted meaning or enforcement. Any change to source authority,
normalization lifecycle, funding semantics, discriminator/versioning,
fingerprint membership, finalization behavior, authorization/RLS, or lock
order requires a new additive migration and independent review.

Migration 014 Financial Billing Basis Hardening remains formally **FROZEN**.
Migration 015 is separately frozen, and Fit Engine implementation is
separately authorized; neither event changes the frozen 014 bytes or meaning.
