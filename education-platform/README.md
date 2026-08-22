# Education Platform Database

SQL-first PostgreSQL/Supabase foundation for an international education
planning product. This milestone contains the catalog schema, provenance and
audit controls, and one golden program record: NYU's MS in Quantitative
Economics for the 2026–27 cycle.

## Local setup

Requirements:

- Docker, or PostgreSQL 15+
- Supabase CLI for the full local Supabase stack (optional)

With Supabase:

```bash
cd education-platform
supabase start
supabase db reset
```

The golden record is a data migration, so `db reset` installs both the schema
and its verified data. `supabase/config.toml` deliberately disables a separate
seed file. The active migration directory contains migrations `001`–`018`.
Migration `015` remains frozen; additive Migration `016` registers the reviewed
Fit Engine v0.1 build and its service-only source projections, and Migration
`017` adds the independently reviewed Financial normalization workflow.

The frozen SQL suites are version-scoped. PostgreSQL 15 retains the original
executor membership grant path; PostgreSQL 16+ uses the authorized
non-superuser `CREATEROLE` compatibility branch while preserving the same
effective `ADMIN` / `INHERIT` / `SET` capabilities. On a fresh PostgreSQL 15
or 17 database, first validate the `001`–`013` baseline and then apply/test
`014`:

Hosted Supabase's `postgres/public` default function ACL is also supported:
012 converges `authenticated` to the two ownership helpers, and 013 removes
external execution from its trigger-only guards without modifying the
platform default ACL.

```bash
for migration in supabase/migrations/2026082000{01..13}_*.sql; do
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$migration"
done
for test_file in \
  supabase/tests/001_education_foundation.sql \
  supabase/tests/002_phase2_eligibility.sql \
  supabase/tests/003_phase3_fit.sql \
  supabase/tests/004_phase012_foundation_hardening.sql \
  supabase/tests/005_phase013_eligibility_v02.sql
do
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$test_file"
done

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f supabase/migrations/202608200014_financial_billing_basis_hardening.sql
for test_file in \
  supabase/tests/001_education_foundation.sql \
  supabase/tests/002_phase2_eligibility.sql \
  supabase/tests/006_phase014_financial_billing_basis_hardening.sql
do
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$test_file"
done
```

After the 014 suite passes, apply and validate 015, then register and validate
the Fit v0.1 production build with 016:

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f supabase/migrations/202608200015_fit_replay_and_seal_hardening.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f supabase/tests/007_phase015_fit_replay_and_seal_hardening.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f supabase/migrations/202608220016_fit_engine_v01_production_registration.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f supabase/tests/008_phase016_fit_engine_production_registration.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f supabase/migrations/202608220017_fit_financial_normalization_workflow.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f supabase/tests/009_phase017_fit_financial_normalization_workflow.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f supabase/migrations/202608220018_fit_v014_private_function_acl_hardening.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f supabase/tests/010_phase018_fit_v014_private_function_acl_hardening.sql
```

Tests `003`, `004`, and `005` are frozen baseline tests and intentionally run
before `014`; `004` and `005` reject leaked `014` objects, while new Financial
assemblies at the `014` head require the v014 witness contract covered by
`006`. The normal SQL tests run inside transactions and roll back their
fixtures. They exit nonzero on any failed assertion.

The concurrency probe is for a disposable database only because its fixture
mode commits rows:

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -v phase014_commit_fixture=1 \
  -f supabase/tests/006_phase014_financial_billing_basis_hardening.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f supabase/tests/_phase014_concurrency_probe.sql
```

For the 015 behavior and concurrency gates, start from the 014 boundary, run
the committed 006 fixture, apply 015, then run:

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -v phase015_behavior_fixture=1 \
  -f supabase/tests/007_phase015_fit_replay_and_seal_hardening.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f supabase/tests/_phase015_concurrency_probe.sql
```

To typecheck and test the pure eligibility library:

```bash
cd packages/eligibility-engine
npm ci
npm test
```

To typecheck and test the pure categorical Fit library:

```bash
cd packages/fit-engine
pnpm install --frozen-lockfile
pnpm test
```

To build and test the production Fit adapter and Edge artifact:

```bash
cd packages/fit-engine-adapter
pnpm install --frozen-lockfile
pnpm test
pnpm bundle:edge
```

The authenticated Financial normalization API is deliberately three-stage:

1. `fit-normalization-prepare` starts one `BUILDING` evaluation, pins the
   amount and `billing_basis`, and creates typed conversion inputs/factors plus
   a `DRAFT` normalization.
2. `fit-normalization-review` requires a different signed-in user whose JWT
   `app_metadata.fit_normalization_reviewer` is `true`; student self-review and
   reuse of conversion evidence as review evidence are rejected.
3. `fit-normalization-resume` reuses the same evaluation after `VERIFIED`
   review, performs versioned exact-decimal same-currency arithmetic, persists
   exact signal provenance, seals fingerprints, and finalizes.

Migration `017` authorizes only `ANNUAL_TO_PROGRAM` and
`ANNUAL_TO_NET_PROGRAM` version 1. Both use the
`FIT_FINANCIAL_NORMALIZATION_CALC_V017` calculation contract, require
`rounding=NONE`, and do not authorize currency conversion. The net method
requires one separate frozen `AVAILABLE_FUNDING` intent on the same signal.

## Migration order

1. `202608200001_core_schema.sql` — catalog and cycle tables.
2. `202608200002_provenance_and_audit.sql` — evidence, canonical selection,
   derived features, external metric scope, audit, and read policies.
3. `202608200003_nyu_msqe_golden_record.sql` — idempotent NYU MSQE data.
4. `202608200004_taxonomy_v01.sql` — stable taxonomy keys and reviewed catalog
   mappings.
5. `202608200005_student_profiles.sql` — privacy boundary, frozen student
   profile versions, raw facts, completeness, evidence, and reviewed mappings.
6. `202608200006_student_derived_features.sql` — reproducible append-only
   derived values, excluded from eligibility v0.1.
7. `202608200007_requirement_rules.sql` — versioned rule trees and controlled
   database verification.
8. `202608200008_eligibility_persistence.sql` — normalized replay manifests and
   append-only rule-level results.
9. `202608200009_fit_contract_registry.sql` — Fit contract/method/evaluator
   registries, the single semantic-source-class registry, mapping/signal
   governance, static input policies, and normalized reason definitions.
10. `202608200010_fit_intents_and_context.sql` — frozen Fit intent snapshots,
    REQUIRED-authority/conflict validation, typed comparison children, and the
    versioned contextual-claim/selection ledger.
11. `202608200011_fit_evaluation_persistence.sql` — evaluations, exact
    manifests, six pinned dimension methods/results, governed signals/reasons,
    sealed input and result fingerprints, controlled finalization, RLS, and
    privacy deletion.
12. `202608200012_frozen_foundation_critical_hardening.sql` — Foundation
    Hardening / Gate 1: function-mediated authorization, lifecycle locking,
    evidence applicability, immutable source revisions, and privacy closure
    over `001`–`011`. Frozen; see
    [docs/PHASE_1_2_FOUNDATION_HARDENING_FREEZE.md](docs/PHASE_1_2_FOUNDATION_HARDENING_FREEZE.md).
13. `202608200013_eligibility_correctness_v02.sql` — Eligibility
    Correctness v0.2: copy-at-use pins, closed-world snapshots,
    sealed replay, projections/`ABSENT`, taxonomy ordinals, and v0.1
    coexistence. Frozen; see
    [docs/PHASE_2_ELIGIBILITY_V02_FREEZE.md](docs/PHASE_2_ELIGIBILITY_V02_FREEZE.md).
14. `202608200014_financial_billing_basis_hardening.sql` — Financial
    `billing_basis` authority, typed normalization inputs/factors, strict
    funding isolation, v014 fingerprints, fail-closed finalization, and
    concurrency-safe lifecycle enforcement. Frozen; see
    [docs/PHASE_3_FINANCIAL_BILLING_BASIS_HARDENING_FREEZE.md](docs/PHASE_3_FINANCIAL_BILLING_BASIS_HARDENING_FREEZE.md).
15. `202608200015_fit_replay_and_seal_hardening.sql` — seal-time semantic
    pinning, pin-only deterministic finalization, legacy 014 dispatch,
    concurrency-safe replay, and privacy-cascade closure. Frozen; see
    [docs/PHASE_3_FIT_REPLAY_AND_SEAL_HARDENING_FREEZE.md](docs/PHASE_3_FIT_REPLAY_AND_SEAL_HARDENING_FREEZE.md).
16. `202608220016_fit_engine_v01_production_registration.sql` — reviewed Fit
    Engine v0.1 evaluator-build registration and service-only bounded snapshot
    functions. It is included in the final Phase 3 v0.1 freeze; see
    [docs/PHASE_3_FREEZE.md](docs/PHASE_3_FREEZE.md).
17. `202608220017_fit_financial_normalization_workflow.sql` — closed production
    annual-to-program and annual-to-net-program methods, service-only DRAFT
    assembly, independent authenticated review, bounded same-evaluation resume
    snapshots, exact-decimal calculation versioning, and least-privilege
    owner/grant boundaries. This is additive and does not modify frozen
    migrations `014` or `015`.
18. `202608220018_fit_v014_private_function_acl_hardening.sql` — ACL-only
    correction that removes implicit external EXECUTE from exactly 13 v014
    private helper/guard functions while retaining the evaluator owner and the
    hosted platform default ACL. It changes no v014–v017 business semantics.

## Rules for data changes

- Never replace an old `program_versions` row to represent a new cycle.
- Unknown facts remain `NULL`; add a field observation with the correct
  knowledge status.
- New canonical rows are checked at transaction commit; every populated
  application-facing field must have a selected observation.
- Add immutable evidence and a `KNOWN` observation before accepting a new
  canonical value.
- Call `select_field_observation(observation_id, actor)` to atomically select
  the current field state. `KNOWN` writes the supported value; non-known states
  such as `SOURCE_CONFLICT` or `STALE` clear the typed value to `NULL`.
- Use `retire_catalog_record(...)` rather than physical deletion. Direct
  canonical updates and physical deletes are rejected.
- Do not write model outputs into source-fact columns.
- External metrics always require granularity, applicability, population
  scope, rationale, and evidence.

See [docs/data-model.md](docs/data-model.md) for details and the currently
unverified NYU fields. See
[docs/phase2-eligibility.md](docs/phase2-eligibility.md) for Phase 2 contracts,
privacy behavior, and deferred scope. Phase 2 Student Eligibility is formally
frozen at v0.1; its authoritative implementation and change-control record is
[docs/PHASE_2_FREEZE.md](docs/PHASE_2_FREEZE.md).

Phase 3 Fit has an approved v0.1 semantic contract in
[docs/PHASE_3_FIT_SPEC.md](docs/PHASE_3_FIT_SPEC.md). Migrations `009`–`011`
persist that contract (registries, intent snapshots, contextual claims, exact
decision manifests, six dimension results, execution integrity, finalization,
RLS, and privacy deletion) and are frozen by
[docs/PHASE_3_DATABASE_FREEZE.md](docs/PHASE_3_DATABASE_FREEZE.md). The
engine implementation contract is
[docs/PHASE_3_FIT_ENGINE_PLAN.md](docs/PHASE_3_FIT_ENGINE_PLAN.md). Phase 3 Fit
v0.1 is **FROZEN** by
[docs/PHASE_3_FREEZE.md](docs/PHASE_3_FREEZE.md). The frozen release includes
the pure categorical evaluator, controlled adapter, registered evaluator
build, authenticated evaluation endpoint, and separate Financial
prepare/review/resume endpoints. It does not implement a score, weight,
ranking, probability, recommendation, Eligibility interpretation, or
Competitiveness model.

Migration `012` Foundation Hardening / Gate 1 is **FROZEN**; its
change-control record is
[docs/PHASE_1_2_FOUNDATION_HARDENING_FREEZE.md](docs/PHASE_1_2_FOUNDATION_HARDENING_FREEZE.md).
Migration 013 — Eligibility Correctness v0.2 is **FROZEN**; its
change-control record is
[docs/PHASE_2_ELIGIBILITY_V02_FREEZE.md](docs/PHASE_2_ELIGIBILITY_V02_FREEZE.md).
The implementation contract remains
[docs/PHASE_2_ELIGIBILITY_V02_PLAN.md](docs/PHASE_2_ELIGIBILITY_V02_PLAN.md).
Migration 014 — Financial Billing Basis Hardening is **FROZEN**; its
change-control record is
[docs/PHASE_3_FINANCIAL_BILLING_BASIS_HARDENING_FREEZE.md](docs/PHASE_3_FINANCIAL_BILLING_BASIS_HARDENING_FREEZE.md).
Migration 015 — Fit Replay and Seal Hardening is **FROZEN**; its
change-control record is
[docs/PHASE_3_FIT_REPLAY_AND_SEAL_HARDENING_FREEZE.md](docs/PHASE_3_FIT_REPLAY_AND_SEAL_HARDENING_FREEZE.md).
Its authorized hosted-runner amendment preserves replay/seal semantics while
restoring the captured installer role after the executor-scoped adoption
update; the freeze record contains the current hash and dual-role regression.
Fit Engine v0.1 production implementation is locally and remotely verified.
Remote migrations `001`–`018` and all four JWT-protected Edge Functions are
deployed; authenticated `evaluate` and independently reviewed
`prepare → review → resume` smoke passed, and temporary users/data were
cleaned up. The release evidence is recorded in
[docs/PHASE_3_PRODUCTION_RELEASE_CANDIDATE.md](docs/PHASE_3_PRODUCTION_RELEASE_CANDIDATE.md),
and the authoritative final state is
[docs/PHASE_3_FREEZE.md](docs/PHASE_3_FREEZE.md).

Phase 4A-1 is implemented, deployed, and remotely verified. Its shared Edge
HTTP boundary release record is
[docs/PHASE_4A1_EDGE_HTTP_BOUNDARY_RELEASE.md](docs/PHASE_4A1_EDGE_HTTP_BOUNDARY_RELEASE.md).
The remaining production observability and minimum product-loop work is still
planning-only in
[docs/PHASE_4_PRODUCTION_OBSERVABILITY_AND_MVP_PLAN.md](docs/PHASE_4_PRODUCTION_OBSERVABILITY_AND_MVP_PLAN.md).
The proposed Application/Outcome data contract is
[docs/MIGRATION_019_APPLICATION_OUTCOME_CONTRACT_PLAN.md](docs/MIGRATION_019_APPLICATION_OUTCOME_CONTRACT_PLAN.md).
No Migration 019 SQL, Application/Outcome runtime, or Competitiveness model is
implemented or authorized by those documents.
The independent plan disposition is recorded in
[docs/PHASE_4_AND_MIGRATION_019_PLAN_REVIEW.md](docs/PHASE_4_AND_MIGRATION_019_PLAN_REVIEW.md).
