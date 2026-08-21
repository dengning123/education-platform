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
seed file.

To validate with any PostgreSQL 15 database:

```bash
for migration in supabase/migrations/*.sql; do
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$migration"
done
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f supabase/tests/001_education_foundation.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f supabase/tests/002_phase2_eligibility.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f supabase/tests/003_phase3_fit.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f supabase/tests/004_phase012_foundation_hardening.sql
```

The SQL tests run inside transactions and roll back their fixtures. They exit
nonzero on any failed assertion.

To typecheck and test the pure eligibility library:

```bash
cd packages/eligibility-engine
npm ci
npm test
```

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
design-only engine milestone is
[docs/PHASE_3_FIT_ENGINE_PLAN.md](docs/PHASE_3_FIT_ENGINE_PLAN.md). Phase 3
overall is **not frozen**, and there is no final Phase 3 tag: no production
evaluator build is registered and there is no Fit TypeScript evaluator, API,
score, ranking, probability, or recommendation implementation.

Migration `012` Foundation Hardening / Gate 1 is **FROZEN**; its
change-control record is
[docs/PHASE_1_2_FOUNDATION_HARDENING_FREEZE.md](docs/PHASE_1_2_FOUNDATION_HARDENING_FREEZE.md).
The next authorized phase is Migration 013 — Eligibility Correctness v0.2.
Fit Engine implementation is not authorized by this freeze.
