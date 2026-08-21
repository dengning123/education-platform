# Phase 2 Eligibility Correctness v0.2 — FROZEN (Migration 013)

Status: **FROZEN**  
Migration: **`202608200013_eligibility_correctness_v02.sql`**  
Milestone: **Eligibility Correctness v0.2**  
Upstream freeze: **Migration 012 Foundation Hardening / Gate 1**  
Freeze date: **2026-08-21**  
Purpose: Record Migration 013 as the approved Eligibility Correctness v0.2
contract over frozen migrations `001`–`012`, without authorizing
Migration 014, Phase 3 Financial hardening, or Fit Engine
implementation.

This record freezes only Eligibility Correctness v0.2 as implemented by
migration `013`. It does not freeze Phase 3 overall, Fit Engine, or a
production-release claim. Migrations `001`–`012` remain unchanged
historical artifacts. Migration `013` must not be edited, reordered,
squashed, or patched in place.

The authoritative sources for this freeze are:

1. [`PHASE_2_ELIGIBILITY_V02_PLAN.md`](PHASE_2_ELIGIBILITY_V02_PLAN.md),
   the 013 design contract;
2. `supabase/migrations/202608200013_eligibility_correctness_v02.sql`,
   the frozen executable migration
   (`sha256:6830d17131ad86d3f5c42edb39883e46def5a2f39e79b8af488b5fd60798332b`);
3. `supabase/tests/005_phase013_eligibility_v02.sql`, the 013 regression
   and adversarial suite, together with the accepted Phase 1/2/3/012 SQL
   and eligibility-engine baseline recorded below.

At freeze time the 013 SQL, 005 tests, v0.2 engine, and plan remain
working-tree artifacts (same docs-only freeze pattern as migration
`012`). This record identifies the freeze-set files and hashes; it does
not rewrite those files.

## 1. Frozen guarantees

The following guarantees are frozen:

1. Eligibility v0.2 is additive on frozen 012 primitives (executor roles,
   function-mediated writes, trusted `search_path`, student lifecycle
   lock identity/order, source revision, evidence applicability). 013
   does not redesign those primitives.
2. Runtime lifecycle authorization remains function-mediated. `service_role`
   has no direct `INSERT`/`UPDATE`/`DELETE` on 013 lifecycle tables;
   named entry points only.
3. `foundation_catalog_executor` `USAGE` on `private` remains false
   (012 D-USAGE unchanged). Taxonomy ordinals reach the private
   allocator only through
   `public.allocate_taxonomy_release_ordinal_v02()`.
4. v0.1 APIs are not overloaded. Discriminator is
   `eligibility_evaluations.input_schema_version`. Historical
   `finalize_eligibility_evaluation(uuid, eligibility_outcome)` remains;
   v0.2 adds `finalize_eligibility_evaluation_v02(uuid)` with no outcome
   argument.
5. After seal, semantic authority is pin/snapshot state. Live
   `mapping_status` is not consulted for v0.2 match, finalize, or replay.
   Later live retirement of a mapping that was `VERIFIED` at pin time
   does not mutate `status_at_pin` and does not change fingerprints.
6. Closed-world snapshot equality holds for degrees, courses, tests, and
   the section 5.0 decision mapping universe (in-scope `VERIFIED` plus
   contract-relevant in-scope `PROPOSED`). `REJECTED` and already-`RETIRED`
   mappings are outside that universe.
7. Five persisted projections are the frozen set: `FULL`,
   `ORDINARY_BARRIER`, `CONDITIONAL_HARD`, `CONDITIONAL_ONLY`,
   `SOFT_EXPLANATION`. Outcome uses only `ORDINARY_BARRIER` ×
   `CONDITIONAL_HARD`. `FULL` root cannot be `ABSENT`.
8. Projected `AT_LEAST` uses explicit reviewer thresholds; no default
   from `minimum_children` outside `FULL`.
9. Canonicalization version is `eligibility-v0.2-c14n1`. Contract names
   are `eligibility-v0.2` / `phase2-v0.2`. Negative-authorization rows
   hash in `result_fingerprint` only.
10. Privacy deletion closes 013 student-owned pin, snapshot, projection,
    and negative-authorization rows through the unchanged
    `delete_student_data` identity and the replaced
    `private.close_student_owned_rows`.
11. Eligibility v0.1 API and semantics remain historical and unchanged.
12. Migration 013 contains no 014 / Fit Engine objects.

## 2. Frozen migration and schema/API boundary

- `202608200013_eligibility_correctness_v02.sql`
  - additive Eligibility Correctness v0.2 over frozen `001`–`012`;
  - taxonomy release ordinals and the public SECURITY DEFINER ordinal
    bridge;
  - evaluation discriminator columns and CHECKs;
  - copy-at-use pins, closed-world snapshots, projection results,
    negative-authorization tables;
  - `start_eligibility_evaluation_v02`, pin insert functions,
    `seal_eligibility_evaluation_inputs_v02`,
    `finalize_eligibility_evaluation_v02`;
  - lock-visibility `SELECT` plus `UPDATE WITH CHECK (false)` on locked
    source parents for `foundation_evaluation_executor`;
  - named 012 `CREATE OR REPLACE` set only (taxonomy create/retire/verify,
    rule-set verify, privacy close, 008 match-insert validator, v0.1
    seal/finalize/result-insert discriminators).

Public v0.2 evaluation entry points are owned by
`foundation_evaluation_executor`, `SECURITY DEFINER`,
`search_path = pg_catalog, public, private, extensions`, `EXECUTE` to
`service_role` only. The catalog threshold writer is owned by
`foundation_catalog_executor` with catalog `search_path`. The ordinal
bridge is owned by the 013 install role (`current_user` at 013 install;
not `foundation_catalog_executor`, not `service_role`),
`search_path = pg_catalog, private`, `EXECUTE` only to
`foundation_catalog_executor`.

PostgREST exposure of v0.2 writers is the `service_role` named-entry
grant only. `anon` / `authenticated` have no `EXECUTE` on those
functions. Owner-read RLS on evaluation-scoped tables uses
`current_user_owns_profile`.

Upstream migrations `001`–`012` are unchanged by this freeze. Phase 2
Eligibility v0.1 remains frozen by
[`PHASE_2_FREEZE.md`](PHASE_2_FREEZE.md). Migration 012 Foundation
Hardening remains frozen by
[`PHASE_1_2_FOUNDATION_HARDENING_FREEZE.md`](PHASE_1_2_FOUNDATION_HARDENING_FREEZE.md).

## 3. v0.1 coexistence contract

The single discriminator is
`public.eligibility_evaluations.input_schema_version`.

| Contract | Start | Seal | Finalize | Schema |
|---|---|---|---|---|
| v0.1 historical | `start_eligibility_evaluation` | `seal_eligibility_evaluation_inputs` | `finalize_eligibility_evaluation(uuid, outcome)` | `eligibility-v0.1` |
| v0.2 | `start_eligibility_evaluation_v02` | `seal_eligibility_evaluation_inputs_v02` | `finalize_eligibility_evaluation_v02(uuid)` | `eligibility-v0.2` |

Cross-version calls fail closed (`eligibility_v01_api_on_v02_row` /
`eligibility_v02_api_on_v01_row`). 013 does not backfill synthetic pins
onto v0.1 rows. Completed v0.1 evaluations remain replayable under the
v0.1 contract until privacy deletion. The v0.1 match-insert branch still
reads live `mapping_status`; the v0.2 branch reads `status_at_pin`.

## 4. Closed-world, projection, and outcome semantics

Seal requires bidirectional equality of profile / identity-manifest /
snapshot membership for degrees, courses, and tests, plus the section
5.0 mapping universe versus mapping pins versus snapshot universe rows.
`UNASSIGNED_CONTEXT` snapshot scopes are always required. 013 does not
modify `freeze_student_profile_version()`. When degrees exist, absence
over `UNASSIGNED_CONTEXT` fails closed to `UNKNOWN`
(`UNASSIGNED_CONTEXT_COMPLETENESS_UNAVAILABLE`); 013 does not fabricate
completeness.

Persisted projections, in order:

| Persisted name | Role |
|---|---|
| `FULL` | every leaf at actual value; `FULL` root cannot be `ABSENT` |
| `ORDINARY_BARRIER` | unavoidable ordinary-hard barrier; conditionals substituted `SATISFIED`; soft `ABSENT` |
| `CONDITIONAL_HARD` | all hard leaves actual; soft `ABSENT` |
| `CONDITIONAL_ONLY` | only `HARD`+`EXPLICIT_CONDITIONAL` leaves; ordinary and soft `ABSENT`; provenance-only |
| `SOFT_EXPLANATION` | only `SOFT` leaves; hard `ABSENT` |

Outcome is derived only from `ORDINARY_BARRIER` × `CONDITIONAL_HARD`
using the plan section 10 4×4 table. `FULL`, `CONDITIONAL_ONLY`, and
`SOFT_EXPLANATION` never own outcome. No new predicate kinds: leaves
remain `HAS_COURSE_CONCEPT` and `HAS_TEST`.

## 5. Replay / pin contract

Each `insert_eligibility_*_pin` copies listed scalars from the locked
source row (`FOR KEY SHARE`) while the evaluation is `BUILDING` and
unsealed. Caller-fabricated `VERIFIED` pins fail
(`eligibility_pin_payload_mismatch` /
`eligibility_mapping_status_not_universe_eligible`).

Seal persists `input_fingerprint` from pins. Finalize of a sealed
`BUILDING` v0.2 row calls
`private.eligibility_v02_assert_closed_world(..., false)` so live
mapping-universe equality is not re-imposed after pin. Leaf decisions
and v0.2 match validation use `status_at_pin`, snapshot membership, and
frozen-profile fact rows (immutable after freeze). Fingerprint replay
after completion is pin-derived; live catalog mapping retirement after
a `VERIFIED` pin does not change hashes.

Live table reads after seal are limited to locks, identity, and frozen
profile fact scalars. They must not reinterpret mapping authority,
canonical selection, or applicability heads.

## 6. Taxonomy ordinal contract

012 remains owner of taxonomy lifecycle. 013 owns ordinals.

- `v0.1` backfills to `release_ordinal = 1`.
- `public.allocate_taxonomy_release_ordinal_v02()` is the sole catalog-
  executor path to `private.taxonomy_allocate_release_ordinal()`.
- `create_taxonomy_release` keeps 012 owner, `service_role` caller, and
  `search_path = pg_catalog, public, extensions`, and does not name
  `private` objects.
- Catalog-executor `USAGE` on `private` remains false.
- `service_role` / `anon` / `authenticated` have no `EXECUTE` on the
  wrapper. Catalog executor has no `EXECUTE` on the private allocator
  and no DML on `private.taxonomy_release_ordinal_allocator`.
- Membership is half-open: `introduced <= pin < retired`.

## 7. Fingerprint / canonicalization versions

Frozen names:

- `input_schema_version`: `eligibility-v0.2`
- `result_semantics_version`: `eligibility-v0.2`
- `canonicalization_version`: `eligibility-v0.2-c14n1`
- `rule_schema_version` / `engine_contract_version` on v0.2 rule sets:
  `phase2-v0.2` / `eligibility-v0.2`
- negative-proof version: `eligibility-v0.2-neg1`

Fingerprint membership is the plan section 11 canonical object schema,
not every storage column. No production canonical-byte payload column.
Negative-authorization rows are result artifacts hashed in
`result_fingerprint` only.

TypeScript v0.2 lives under `packages/eligibility-engine/src/v02/` with
contract `packages/eligibility-engine/contracts/eligibility-v0.2.json`.
Existing v0.1 `evaluateEligibility` remains historically compatible and
is not overloaded.

## 8. Privacy contract

`delete_student_data` identity is unchanged. 013 replaces only
`private.close_student_owned_rows` to anti-join 013 student-owned pin,
snapshot, projection, negative-authorization, and finalize-authorization
rows. Deletion leaves the 012 non-PII tombstone. Catalog and taxonomy
history survive. Privacy deletion ends full replayability of student-
owned evaluations.

## 9. Explicitly excluded scope

The following are not part of this freeze and are not authorized by it:

- Migration 014 / Phase 3 Financial `billing_basis` hardening;
- Fit Engine implementation, evaluator-build registration, API, score,
  ranking, probability, or recommendation systems;
- in-place patches to migration `013` semantics;
- hosted JWT / GoTrue / PostgREST production-release certification;
- a sixth projection enum value, `HAS_DEGREE`, or fabricated
  `UNASSIGNED_CONTEXT` completeness.

## 10. Accepted validation baseline

Independent freeze-review proof (repo code, not a hosted re-run):

- migrations `001`–`012` tracked diff: **empty**
- migration `013` semantically unedited during this freeze task
- no `014` migration file
- 013 SQL: no `TODO` / `FIXME`
- tests `001` / `002` adaptations retain historical assertion messages
  and use 012 named APIs rather than bypasses
- `005` executable gates A–I call production start / pin-insert / seal /
  finalize paths (`start_eligibility_evaluation_v02`,
  `insert_eligibility_*_pin`, `seal_eligibility_evaluation_inputs_v02`,
  `finalize_eligibility_evaluation_v02`); omit/extra/universe attacks
  expect production hints
- TAX-AUTH-1 through TAX-AUTH-8 encoded in `005`
- v0.1 engine tests remain under `test/evaluate.test.ts` (8 tests);
  v0.2 module is additive

Established 013 hardening-suite claims accepted as the freeze test
baseline (local PostgreSQL 15 / 012-role model; not re-executed in this
docs-only freeze):

- clean migrations 001–013
- populated 012→013 upgrade
- Phase 1/2/3/012 SQL still green
- 005 phase 013 assertions and executable gates
- eligibility-engine v0.1 8/8 plus v0.2 module / parity corpus
- catalog-executor `USAGE(private)` remains false
- no 014 / Fit Engine objects

## 11. Known non-blocking cautions

These cautions are recorded separately. They are **not** frozen semantic
defects and do not reopen the 013 contract:

- hosted Supabase JWT / GoTrue / PostgREST integration remains a
  production-release check (local `auth.uid()` is a bootstrap stub);
- 013 install owner is `current_user` of the migration (typically
  `postgres` locally), matching 012’s install-authority pattern rather
  than a dedicated `foundation_migration_owner` role name;
- lock-visibility `SELECT` for executors uses `USING (true)` for
  catalog/student/evaluation executors; mutation remains
  `UPDATE … WITH CHECK (false)` for the evaluation executor, proven in
  013 post-install assertions and `005` AUTH-LOCK probes;
- plan section 16.J two-session finalize-versus-delete coverage is
  partial (`TAX-AUTH-5` concurrent ordinal allocation is present;
  `005` labels A–I as the executable production-path gates);
- 004 dblink fixtures may autocommit outside rollback (012 freeze
  residual, unchanged);
- 013 SQL / 005 / v0.2 engine remain untracked working-tree files at
  freeze-doc commit time, as 012 SQL did at the 012 docs freeze.

Hosted JWT/GoTrue/PostgREST verification remains a production-release
check. It does not invalidate this freeze and does not authorize
rewriting 013.

## 12. Post-freeze change policy

013 semantics cannot be patched in place. Further changes require a new
additive migration.

The following may proceed without a new migration only when they do not
alter persisted meaning or enforcement:

- documentation clarification;
- additive tests that prove already frozen behavior;
- query or index optimization with unchanged observable behavior.

The following require a new additive migration:

- changing executor-role, function-mediated authorization, direct-DML,
  lock-visibility, or trusted `search_path` primitives;
- changing pin/snapshot/universe membership, closed-world equality, or
  sealed-replay authority;
- changing projection names, `ABSENT` propagation, or the 4×4 outcome
  table;
- changing taxonomy ordinal allocation or catalog-executor `USAGE` on
  `private`;
- changing fingerprint membership or canonicalization version;
- changing v0.1 coexistence discriminators or v0.1 match-insert live
  checks;
- changing privacy deletion closure for 013 student-owned rows;
- introducing 014 Financial or Fit Engine semantics.

This freeze does not authorize Migration 014 or Fit Engine
implementation. If later work needs a new semantic capability, it must
be additive on top of the frozen 012 primitives and this 013 contract.

## 13. Freeze boundary

Migration 013 Eligibility Correctness v0.2 is formally **FROZEN**.

This freeze does not authorize Migration 014, Fit Engine implementation,
or a production-release claim.
