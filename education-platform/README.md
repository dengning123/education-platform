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
