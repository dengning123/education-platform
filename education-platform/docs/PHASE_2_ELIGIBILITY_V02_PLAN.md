# Phase 2 Eligibility Correctness v0.2 — FINAL IMPLEMENTATION PLAN

Status: **IMPLEMENTED — UNFROZEN, READY FOR FREEZE RE-REVIEW**  
Date: **2026-08-20**  
Revision: **013 hardened: copy-at-use pins, closed-world universes, sealed replay, canonical numerics, semantic fingerprints, lock-visibility RLS; taxonomy ordinal wrapper remains `public.allocate_taxonomy_release_ordinal_v02()`; catalog executor USAGE on private remains false. This is not a freeze record.**  
Migration: **`202608200013_eligibility_correctness_v02.sql`**  
Test file: **`supabase/tests/005_phase013_eligibility_v02.sql`**  
Upstream freeze: **Migration 012 Foundation Hardening / Gate 1**  
Freeze record: [`PHASE_1_2_FOUNDATION_HARDENING_FREEZE.md`](PHASE_1_2_FOUNDATION_HARDENING_FREEZE.md)  
Freeze commit: **`ec6119ce`**  
013 ownership source: [`PHASE_1_2_FOUNDATION_REMEDIATION_PLAN.md`](PHASE_1_2_FOUNDATION_REMEDIATION_PLAN.md) sections 1.1, 1.3, 1.4, 9B, 12–16, 18

This document is the Gate 2 implementation contract for Eligibility
Correctness v0.2. 013 is implemented and unfrozen; this is not a freeze
record, does not modify migrations `001`–`012`, does not start 014, and
does not resume Fit Engine work. Semantic meaning is unchanged from the
approved plan except where this file records now-implemented invariants
(copy-at-use pins, closed-world universes, sealed replay, canonical
numerics, semantic fingerprints, lock-visibility RLS).

013 is additive on frozen 012 primitives:

- executor-role model (`foundation_catalog_executor`,
  `foundation_student_executor`, `foundation_evaluation_executor`);
- direct-DML policy (runtime `INSERT`/`UPDATE`/`DELETE` revoked; function-
  mediated writes only);
- trusted `search_path` (`pg_catalog, public, extensions` catalog;
  `pg_catalog, public, private, extensions` student/evaluation; no `pg_temp`
  on entry points);
- frozen 012 D-USAGE: `foundation_catalog_executor` has `USAGE` on
  `private` = false; 013 does not grant it; taxonomy ordinals reach the
  private allocator only through
  `public.allocate_taxonomy_release_ordinal_v02()`;
- student lifecycle lock identity/order
  (`private.lock_student_lifecycle(uuid)` first, then
  `private.lock_student_owned_total_order(uuid)`);
- source revision model and source/current-head locking;
- evidence applicability model (nine-part `REVIEWED_APPLICABLE` for new
  `KNOWN`; `LEGACY_UNASSERTED` historical only).

If 013 needs a new semantic capability, it is a new object or a named
`CREATE OR REPLACE` listed in section 1. It does not invent a policy DSL,
capability system, or event-sourcing log.

---

## 0. Decisions that close prior naming conflicts

These decisions are binding. They are not alternatives.

1. **Five persisted projections are the frozen remediation set**, not a sixth
   name. User-facing “HARD_CURRENT” is **not** a stored label. It is the
   informal description of `CONDITIONAL_HARD` (all hard leaves at their
   actual current values). Persisted names, in order:

   | Persisted name | Informal alias | Role |
   |---|---|---|
   | `FULL` | full tree | every leaf at actual value; `FULL` root cannot be `ABSENT` |
   | `ORDINARY_BARRIER` | ordinary-hard | unavoidable ordinary-hard barrier; conditionals substituted `SATISFIED`; soft `ABSENT` |
   | `CONDITIONAL_HARD` | hard-current | all hard leaves actual; soft `ABSENT` |
   | `CONDITIONAL_ONLY` | conditional explanation | only `HARD`+`EXPLICIT_CONDITIONAL` leaves; ordinary and soft `ABSENT` |
   | `SOFT_EXPLANATION` | soft explanation | only `SOFT` leaves; hard `ABSENT` |

   Outcome uses only `ORDINARY_BARRIER` × `CONDITIONAL_HARD`. The section 10
   4×4 table is the sole authoritative ordinary × conditional source;
   surrounding prose is commentary. `FULL`, `CONDITIONAL_ONLY`, and
   `SOFT_EXPLANATION` never own outcome. `CONDITIONAL_ONLY` is explanatory
   / provenance-only.

2. **User “DEGREE_HISTORY” is the existing domain `EDUCATION_HISTORY`.**
   013 does not add a `student_data_domain` value. Education context identity
   is `student_degrees.student_degree_id`. Courses with
   `student_degree_id IS NULL` belong to `UNASSIGNED_CONTEXT`.

3. **No new predicate kinds.** v0.2 leaves remain `HAS_COURSE_CONCEPT` and
   `HAS_TEST`. Degree snapshots exist so education-context partition and
   `EDUCATION_HISTORY` completeness are closed-world. v0.2 does not
   introduce `HAS_DEGREE` or any degree-absence negative predicate.

4. **Negative-authorization rows are result artifacts.** They are hashed in
   `result_fingerprint` only. Completeness pins and snapshot membership are
   input. This matches remediation §15.3–15.4 and rejects mixing derived
   proof into the input hash.

5. **v0.1 APIs are not overloaded.** Historical
   `finalize_eligibility_evaluation(uuid, eligibility_outcome)` remains.
   013 adds `finalize_eligibility_evaluation_v02(uuid)` with no outcome
   argument. Discriminator is `eligibility_evaluations.input_schema_version`.

6. **Named 012 `CREATE OR REPLACE` set is closed.** 013 may replace only:

   - taxonomy: `create_taxonomy_release(text,timestamptz,text)`,
     `verify_taxonomy_release(text,text)`,
     `create_taxonomy_concept(taxonomy_concepts)`,
     `create_taxonomy_alias(taxonomy_aliases)`,
     `create_taxonomy_relationship(taxonomy_relationships)`,
     `retire_taxonomy_concept(uuid,text,text)`,
     `retire_taxonomy_alias(uuid,text,text)`,
     `retire_taxonomy_relationship(uuid,text,text)`;
   - rules: `verify_program_requirement_rule_set(uuid,text,uuid)`;
   - privacy: `private.close_student_owned_rows(uuid)`;
   - 008 match-insert validator (additive compatibility override; 013
     does not edit file `202608200008_eligibility_persistence.sql`):
     `public.validate_eligibility_match_insert()` — the exact function
     executed by 008 triggers `eligibility_course_matches_validate` and
     `eligibility_test_matches_validate`. Trigger and table identities
     stay. Replacement body branches on
     `eligibility_evaluations.input_schema_version` (section 5.4);
   - coexistence discriminators (same identity arguments, owner, callers,
     `search_path`, lock identity; body change is a version-gate only):
     `seal_eligibility_evaluation_inputs(uuid)`,
     `finalize_eligibility_evaluation(uuid,eligibility_outcome)`,
     `insert_eligibility_requirement_result(eligibility_requirement_results)`,
     `insert_eligibility_course_match(eligibility_course_matches)`,
     `insert_eligibility_test_match(eligibility_test_matches)`.

   `delete_student_data(uuid,text)`, `lock_student_lifecycle`,
   `lock_student_owned_total_order`, `freeze_student_profile_version`,
   executor roles, grants, evidence applicability, and source revision
   functions are not replaced. `create_taxonomy_release` replacement
   preserves 012 owner, callers, and catalog `search_path`; its body
   calls `public.allocate_taxonomy_release_ordinal_v02()` (a new 013
   identity in sections 1.5 and 7.2, not a 012 replace).

7. **`UNASSIGNED_CONTEXT` is evaluation-time snapshot scope, not a Phase 2
   completeness identity.** Inspected 012
   `freeze_student_profile_version` `required_scope` (same rule as 005
   `guard_student_profile_version`): NULL-context `COURSE_HISTORY` /
   `COURSE_MAPPING` completeness is required **only when the profile has
   zero degrees**. When one or more degrees exist, 012 requires only
   per-degree `COURSE_*` completeness. No 012 required scope covers
   courses with `student_degree_id IS NULL` in that case. Per-degree
   `COURSE_*`, global `EDUCATION_HISTORY`, and global `TEST_HISTORY` do
   not safely cover those records. 013 therefore does not fabricate
   completeness, does not infer `COMPLETE` from other completeness rows,
   and does not modify `freeze_student_profile_version()`. When degrees
   exist, absence over `UNASSIGNED_CONTEXT` fails closed to `UNKNOWN`
   (`UNASSIGNED_CONTEXT_COMPLETENESS_UNAVAILABLE`). Section 3.4.

8. **Projected `AT_LEAST` uses explicit reviewer thresholds**, stored in
   immutable `requirement_group_projection_thresholds` keyed by
   `(rule_set_id, group_node_id, projection_kind)`. No default from
   `minimum_children`, no subtraction, no runtime inference. `FULL` uses
   the original `minimum_children`. Section 8.5.

   “Explicit” is literal for every non-`FULL` projection, including a
   projection that happens to retain every immediate structural child. No
   equality-to-`minimum_children` shortcut is permitted outside `FULL`.

9. **Fingerprint membership is the section 11 canonical object schema**,
   not every storage column on pin/snapshot/result tables.

10. **Fit locks and Fit domain states are not part of the v0.2 Eligibility
    finalizer.** The finalizer may call the unchanged 012
    `lock_student_owned_total_order` (which serializes Fit-owned families
    for student-lock hygiene) but must not read Fit evaluation state,
    Fit intents, Fit completeness, or any Fit domain as eligibility
    input or outcome.

11. **The v0.2 decision mapping universe is not every historical mapping
    row.** It contains only mappings semantically relevant at the
    evaluation pin/start boundary (section 5.0). This is the sole
    mapping-pin identity law. No later section may require
    identity-only pins for `REJECTED` / already-`RETIRED` mappings, nor
    equate “every 008 identity-manifest mapping” with the required pin
    set.

    | Status at the pin boundary | Pin? | Universe role | May satisfy | May cause UNKNOWN |
    |---|---|---|---|---|
    | `VERIFIED` (in scope) | **MUST** pin | `AUTHORITATIVE` | yes, if the relation is authorized | no by itself |
    | `PROPOSED` (contract-relevant, in scope) | pin **only** as limiting evidence | `LIMITING` | **MUST NOT** | yes, where the contract requires |
    | `REJECTED` | **MUST NOT** pin | outside universe | **MUST NOT** | **MUST NOT** independently |
    | already `RETIRED` | **MUST NOT** pin | outside universe | **MUST NOT** | **MUST NOT** independently |

    Required evaluation mapping universe = in-scope `VERIFIED` +
    contract-relevant in-scope `PROPOSED`. `REJECTED` and already-
    `RETIRED` are excluded from **both** sides. Later live retirement
    of a mapping that was `VERIFIED` at pin time does not mutate
    `status_at_pin` and does not invalidate match, finalize, or replay.

12. **Taxonomy ordinals use one public SECURITY DEFINER bridge.** Frozen
    012 D-USAGE is not amended: `foundation_catalog_executor` has
    `USAGE` on `private` = false after 013. `create_taxonomy_release`
    keeps its 012 owner, callers, and
    `search_path = pg_catalog, public, extensions`, and therefore never
    names `private` objects. 013 installs
    `public.allocate_taxonomy_release_ordinal_v02()` as the sole
    catalog-executor path to `private.taxonomy_release_ordinal_allocator`.
    Section 7 is the sole ordinal-authorization source. No later
    section may grant catalog-executor `USAGE` on `private`, move the
    allocator into `public`, or put `private` on
    `create_taxonomy_release`’s `search_path`.

---

## 1. Exact new and changed 013 objects

### 1.1 New enum types

```sql
create type public.eligibility_projection as enum (
  'FULL',
  'ORDINARY_BARRIER',
  'CONDITIONAL_HARD',
  'CONDITIONAL_ONLY',
  'SOFT_EXPLANATION'
);

create type public.eligibility_projection_value as enum (
  'SATISFIED',
  'NOT_SATISFIED',
  'UNKNOWN',
  'ABSENT'
);

create type public.eligibility_snapshot_scope_kind as enum (
  'GLOBAL_PROFILE',
  'EDUCATION_CONTEXT',
  'UNASSIGNED_CONTEXT'
);

create type public.eligibility_mapping_universe_role as enum (
  'AUTHORITATIVE',
  'LIMITING'
);

create type public.eligibility_student_mapping_relation as enum (
  'STUDENT_CONCEPT_ASSOCIATION'
);

create type public.eligibility_v02_missing_data_code as enum (
  'PROGRAM_FACT_NOT_KNOWN',
  'MAPPED_COURSE_NOT_INCLUDED',
  'COURSE_EDUCATION_CONTEXT_MISMATCH',
  'INCOMPLETE_COURSE_OR_MAPPING_COVERAGE',
  'NO_VERIFIED_MAPPING',
  'PROPOSED_MAPPING_LIMITING',
  'INCOMPLETE_TEST_HISTORY',
  'INCOMPLETE_EDUCATION_HISTORY',
  'TAXONOMY_CONCEPT_INACTIVE_AT_PIN',
  'UNASSIGNED_CONTEXT_COMPLETENESS_UNAVAILABLE'
);
```

`requirement_truth_value` stays three-state. `ABSENT` is stored only in
`eligibility_requirement_projection_results.value`.
`eligibility_requirement_results.truth_value` on v0.2 rows is the `FULL`
three-state value and is never `ABSENT`.

### 1.2 Additive columns on existing tables

**`taxonomy_releases`**

| Column | Type | Null | Rule |
|---|---|---|---|
| `release_ordinal` | `bigint` | NOT NULL after backfill | immutable, unique, `>= 1` |

Existing `v0.1` → ordinal `1`. Any additional 012-created releases receive
consecutive ordinals ordered by `created_at`, then `release_code`.

**`taxonomy_concepts`, `taxonomy_aliases`, `taxonomy_relationships`**

| Column | Type | Null | Rule |
|---|---|---|---|
| `introduced_release_ordinal` | `bigint` | NOT NULL after backfill | copy of introducing release ordinal; `>= 1` |
| `retired_release_ordinal` | `bigint` | nullable | set only by retire-at-release; if present, `introduced_release_ordinal < retired_release_ordinal` |

Ordinal backfill is mechanical for **all** pre-013 content, not only the
golden v0.1 rows:

- assign every existing release one unique ordinal by `created_at`, then
  `release_code`; the release with code `v0.1` must receive ordinal `1`;
- for every concept/alias/relationship,
  `introduced_release_ordinal` is the ordinal of its existing
  `introduced_in_release` code;
- when existing `retired_in_release` is non-null,
  `retired_release_ordinal` is that release's ordinal; otherwise it is NULL;
- abort 013 with `55000` before adding NOT NULL/check constraints if a
  referenced release code is missing, `v0.1` is not the first ordered
  release, or any derived interval is empty/reversed;
- no text release code or historical taxonomy row is rewritten.

Thus golden v0.1 content backfills introduced `1`, retired `NULL`, while a
populated 012 database with later releases preserves its existing lifecycle
semantics by exact release-code lookup.

**`program_requirement_rule_sets`**

Replace `program_rule_sets_supported_contract` with:

```sql
(
  rule_schema_version = 'phase2-v0.1'
  and engine_contract_version = 'eligibility-v0.1'
)
or (
  rule_schema_version = 'phase2-v0.2'
  and engine_contract_version = 'eligibility-v0.2'
)
```

Historical v0.1 rows keep `phase2-v0.1` / `eligibility-v0.1`. Mixed pairs
fail. No v0.1 row is rewritten.

**`eligibility_evaluations`**

| Column | Type | v0.1 | v0.2 BUILDING unsealed | v0.2 BUILDING sealed | v0.2 COMPLETED |
|---|---|---|---|---|---|
| `input_schema_version` | text | `eligibility-v0.1` | `eligibility-v0.2` | same | same |
| `result_semantics_version` | text | NULL | `eligibility-v0.2` | same | same |
| `canonicalization_version` | text | NULL | `eligibility-v0.2-c14n1` | same | same |
| `contract_release_code` | text | NULL | `phase2-v0.2` | same | same |
| `taxonomy_release_ordinal` | bigint | NULL | pinned ordinal `>= 1` | same | same |
| `input_fingerprint` | text | NULL until COMPLETED | NULL | 64 lowercase hex | same hex |
| `result_fingerprint` | text | NULL always | NULL | NULL | 64 lowercase hex |
| `outcome` / `root_truth_value` / `evaluated_at` | existing | NULL until COMPLETED | NULL | NULL | set by v0.2 finalizer |

Discriminator `eligibility_evaluations_version_gate`:

```text
(input_schema_version = 'eligibility-v0.1'
   and result_semantics_version is null
   and canonicalization_version is null
   and contract_release_code is null
   and taxonomy_release_ordinal is null
   and result_fingerprint is null
   and (evaluation_state = 'BUILDING'
        implies input_fingerprint, outcome, root_truth_value,
                evaluated_at are null)
   and (evaluation_state = 'COMPLETED'
        implies those four plus input_fingerprint are not null))
OR
(input_schema_version = 'eligibility-v0.2'
   and result_semantics_version = 'eligibility-v0.2'
   and canonicalization_version = 'eligibility-v0.2-c14n1'
   and contract_release_code = 'phase2-v0.2'
   and taxonomy_release_ordinal >= 1
   and (evaluation_state = 'BUILDING' and inputs_sealed_at is null
        implies input_fingerprint, result_fingerprint, outcome,
                root_truth_value, evaluated_at are null)
   and (evaluation_state = 'BUILDING' and inputs_sealed_at is not null
        implies input_fingerprint ~ '^[a-f0-9]{64}$'
            and result_fingerprint, outcome, root_truth_value,
                evaluated_at are null)
   and (evaluation_state = 'COMPLETED'
        implies input_fingerprint and result_fingerprint ~ '^[a-f0-9]{64}$'
            and outcome, root_truth_value, evaluated_at, inputs_sealed_at
                are not null))
```

Drop `eligibility_evaluations_identity_not_blank`’s hard-coded
`'eligibility-v0.1'` equality and `eligibility_evaluations_root_outcome`.
Replace with:

- v0.1-only `eligibility_evaluations_v01_root_outcome` copying the 008
  root/outcome matrix, predicated on
  `input_schema_version = 'eligibility-v0.1'`;
- v0.2-only `eligibility_evaluations_v02_root_is_full` requiring
  `root_truth_value is null or root_truth_value in
  ('SATISFIED','NOT_SATISFIED','UNKNOWN')` with no outcome coupling
  (`FULL` root does not determine outcome).

No production column stores canonical JSON or canonical bytes.

### 1.3 New catalog tables (not student-owned)

```sql
create table private.taxonomy_release_ordinal_allocator (
  singleton boolean primary key check (singleton),
  next_ordinal bigint not null check (next_ordinal >= 2)
);
-- exactly one row after backfill: (true, max(release_ordinal)+1)
-- catalog executor has no USAGE on private and no DML on this table.

create table public.requirement_group_projection_thresholds (
  rule_set_id uuid not null
    references public.program_requirement_rule_sets(rule_set_id)
    on delete restrict,
  group_node_id uuid not null
    references public.program_requirement_nodes(rule_node_id)
    on delete restrict,
  projection_kind public.eligibility_projection not null,
  projected_minimum_children integer not null
    check (projected_minimum_children >= 1),
  projected_descendant_count integer not null
    check (projected_descendant_count >= 1),
  verification_evidence_id uuid,
  verified_by text,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (rule_set_id, group_node_id, projection_kind),
  foreign key (rule_set_id, group_node_id)
    references public.program_requirement_nodes(rule_set_id, rule_node_id)
    on delete restrict,
  check (projected_minimum_children <= projected_descendant_count)
);
```

Immutable catalog rows. Direct DML revoked from runtime roles. Not
privacy-deleted. Writers:

- catalog-executor `insert_requirement_group_projection_threshold` on a
  `DRAFT` `eligibility-v0.2` rule set, **only** for
  `projection_kind ∈ {ORDINARY_BARRIER, CONDITIONAL_HARD,
  CONDITIONAL_ONLY, SOFT_EXPLANATION}`;
- the 013 replacement of `verify_program_requirement_rule_set` writes
  the normalized `FULL` row from `minimum_children` when
  `projected_descendant_count > 0`, stamps review provenance
  (`verification_evidence_id`, `verified_by`, `verified_at`) on every
  stored row from the verify arguments, and then the rows are immutable.

Required only for `AT_LEAST` groups with at least one projected
descendant in that `projection_kind`. Not stored when the projected
descendant count is 0 (`ABSENT`). `1 <= projected_minimum_children <=
projected_descendant_count`. No default from `minimum_children` on the
four non-`FULL` projections. No subtraction formula. No runtime
inference. Frozen when the v0.2 rule set becomes `VERIFIED`.
Completed evaluations pin the exact threshold identity and value.

### 1.4 New evaluation-scoped tables (student-owned, cascade)

Every table below has `evaluation_id uuid not null references
public.eligibility_evaluations(evaluation_id) on delete cascade`.
Append-only while `BUILDING` and unsealed; immutable after seal/finalize.
Direct DML revoked. Writers are the 9B insert functions or the v0.2
finalizer.

**Replay pins**

- `eligibility_rule_set_pins(evaluation_id PK, rule_set_id, program_version_id,
  rule_set_version, taxonomy_release_code, taxonomy_release_ordinal,
  rule_schema_version, engine_contract_version, verification_evidence_id,
  verified_by, verified_at)`
- `eligibility_rule_node_pins(evaluation_id, rule_node_id, parent_node_id,
  sort_order, node_kind, group_operator, minimum_children, predicate_kind,
  requirement_strength, requirement_semantics, target_concept_id,
  explanation_template, PK(evaluation_id, rule_node_id))`
- `eligibility_rule_node_source_pins(evaluation_id, rule_node_id,
  field_observation_id, source_id, applicability_assertion_id,
  applicability_head_assertion_id_at_pin, applicability_scope_id,
  knowledge_status_at_pin,
  PK(evaluation_id, rule_node_id, field_observation_id))`
- `eligibility_rule_node_mapping_pins(evaluation_id, rule_node_id,
  catalog_mapping_id, PK(evaluation_id, rule_node_id, catalog_mapping_id))`
- `eligibility_projection_threshold_pins(evaluation_id, rule_set_id,
  group_node_id, projection_kind, projected_minimum_children,
  projected_descendant_count, verification_evidence_id, verified_by,
  verified_at, created_at_source,
  PK(evaluation_id, group_node_id, projection_kind))`
- `eligibility_catalog_observation_pins(evaluation_id, field_observation_id,
  source_id, source_identity_id, source_revision_number,
  retrieval_content_hash, evidence_id, record_type, record_id, field_name,
  canonical_value jsonb, knowledge_status, program_scope_key,
  program_version_scope_key, granularity_scope, population_scope_code,
  cycle_scope_code, PK(evaluation_id, field_observation_id))`
- `eligibility_catalog_selection_pins(evaluation_id, record_type, record_id,
  field_name, observation_id, selected_at_pin, selected_by_pin,
  PK(evaluation_id, record_type, record_id, field_name))`
- `eligibility_catalog_mapping_pins(evaluation_id, catalog_mapping_id,
  record_type, record_id, concept_id, relation_at_pin, method, confidence,
  model_version, verification_evidence_id, reviewed_by, reviewed_at,
  status_at_pin, retired_at_pin, retirement_reason_at_pin,
  PK(evaluation_id, catalog_mapping_id))`
- `eligibility_student_mapping_pins(evaluation_id, student_mapping_id,
  profile_version_id, record_type, student_record_id, concept_id,
  relation_at_pin, method, confidence, model_version, student_evidence_id,
  reviewed_by, reviewed_at, status_at_pin, retired_at_pin,
  retirement_reason_at_pin,
  PK(evaluation_id, student_mapping_id))`
- `eligibility_taxonomy_concept_pins(evaluation_id, concept_id, canonical_key,
  concept_kind, introduced_release_ordinal, retired_release_ordinal,
  PK(evaluation_id, concept_id))`
- `eligibility_completeness_pins(evaluation_id, completeness_id, scope_id,
  domain, completeness, explanation,
  PK(evaluation_id, completeness_id))`
  `scope_id` is nullable. It is set only when the upstream completeness
  row is the 012-required identity for a snapshot scope. When the
  completeness row has no 012 applicability scope, `scope_id` stays
  NULL. 013 does not fabricate a scope.

`relation_at_pin` on student pins is
`eligibility_student_mapping_relation` and is always
`STUDENT_CONCEPT_ASSOCIATION` (005 has no relation column). Catalog
`relation_at_pin` is `catalog_mapping_relation`. `status_at_pin` is
`mapping_status`.

**Domain snapshots / universes**

- `eligibility_snapshot_scopes(scope_id uuid PK, evaluation_id,
  profile_version_id, scope_kind, education_context_id, domain,
  completeness_id, completeness,
  unique (evaluation_id, scope_kind, education_context_id, domain)
  NULLS NOT DISTINCT)`
  `completeness_id` / `completeness` are NOT NULL except the one case
  in section 3.4: `UNASSIGNED_CONTEXT` when the frozen profile has
  one or more degrees (no 012 completeness authority).
- `eligibility_snapshot_degrees(scope_id, student_degree_id,
  PK(scope_id, student_degree_id))`
- `eligibility_snapshot_courses(scope_id, student_course_id,
  PK(scope_id, student_course_id))`
- `eligibility_snapshot_test_scores(scope_id, student_test_score_id,
  PK(scope_id, student_test_score_id))`
- `eligibility_snapshot_mapping_universe(scope_id, student_mapping_id,
  universe_role, PK(scope_id, student_mapping_id))`

FK `scope_id → eligibility_snapshot_scopes` ON DELETE CASCADE.
FK membership IDs also to the matching 008 manifest tables
(`eligibility_manifest_degrees` / `_courses` / `_test_scores` /
`_student_mappings`) so a snapshot/universe member ID cannot exist
without that manifest ID. For degrees, courses, and tests, seal still
proves bidirectional set equality against the frozen profile. For
mappings, the required set is the section 5.0 decision universe, not
every historical mapping row of the profile.

`eligibility_snapshot_mapping_universe` contains only the section 5.0
decision mapping universe (`VERIFIED` as `AUTHORITATIVE`, contract-
relevant `PROPOSED` as `LIMITING`). The 008 student-mapping identity
manifest is **not** the decision universe. `REJECTED` and already-
`RETIRED` mappings remain upstream history only: they MUST NOT be
pinned, MUST NOT receive a universe row, and are excluded from both
sides of mapping-universe equality. Presence or absence of those
historical rows in `eligibility_manifest_student_mappings` does not
create a pin obligation and does not change the input fingerprint.
Seal proves section 5.0 / 5.1; it does **not** assert “every identity-
manifest mapping ID has a pin.”

**Finalizer-only result tables**

- `eligibility_requirement_projection_results(evaluation_id, rule_node_id,
  projection, value, PK(evaluation_id, rule_node_id, projection))`
- `eligibility_negative_fact_authorizations(evaluation_id, rule_node_id,
  domain, proof_version text not null default 'eligibility-v0.2-neg1',
  created_at, PK(evaluation_id, rule_node_id))`
- `eligibility_negative_authorization_scopes(evaluation_id, rule_node_id,
  scope_id, PK(evaluation_id, rule_node_id, scope_id))`

`proof_version` is the closed literal `eligibility-v0.2-neg1`. No JSON
proof payload.

**Write authorization (private, not hashed)**

```sql
create table private.eligibility_v02_finalize_authorizations (
  transaction_id bigint not null,
  evaluation_id uuid not null,
  executor_role text not null
    check (executor_role = 'foundation_evaluation_executor'),
  primary key (transaction_id, evaluation_id)
);
```

Mirrors 012 `student_deletion_authorizations`. Exists only inside
`finalize_eligibility_evaluation_v02`. Guards on result/projection/negative/
match tables accept INSERT for a v0.2 evaluation only when this row exists
for `txid_current()`. No GUC is used.

### 1.5 New / replaced functions

**Public evaluation executor (`service_role` EXECUTE, evaluation-executor
owner, `search_path = pg_catalog, public, private, extensions`)**

| Signature | Role |
|---|---|
| `start_eligibility_evaluation_v02(uuid,uuid,text,text,text,text)` | start BUILDING v0.2 row |
| `insert_eligibility_rule_set_pin(eligibility_rule_set_pins)` | pin copy |
| `insert_eligibility_rule_node_pin(eligibility_rule_node_pins)` | pin copy |
| `insert_eligibility_rule_node_source_pin(eligibility_rule_node_source_pins)` | pin copy |
| `insert_eligibility_rule_node_mapping_pin(eligibility_rule_node_mapping_pins)` | pin copy |
| `insert_eligibility_projection_threshold_pin(eligibility_projection_threshold_pins)` | pin copy |
| `insert_eligibility_catalog_selection_pin(eligibility_catalog_selection_pins)` | pin copy |
| `insert_eligibility_catalog_observation_pin(eligibility_catalog_observation_pins)` | pin copy |
| `insert_eligibility_catalog_mapping_pin(eligibility_catalog_mapping_pins)` | pin copy |
| `insert_eligibility_student_mapping_pin(eligibility_student_mapping_pins)` | pin copy |
| `insert_eligibility_taxonomy_concept_pin(eligibility_taxonomy_concept_pins)` | pin copy |
| `insert_eligibility_completeness_pin(eligibility_completeness_pins)` | pin copy |
| `insert_eligibility_snapshot_scope(eligibility_snapshot_scopes)` | snapshot |
| `insert_eligibility_snapshot_degree(eligibility_snapshot_degrees)` | membership |
| `insert_eligibility_snapshot_course(eligibility_snapshot_courses)` | membership |
| `insert_eligibility_snapshot_test_score(eligibility_snapshot_test_scores)` | membership |
| `insert_eligibility_snapshot_mapping_universe(eligibility_snapshot_mapping_universe)` | universe |
| `seal_eligibility_evaluation_inputs_v02(uuid)` | seal + persist input hash |
| `finalize_eligibility_evaluation_v02(uuid)` | derive all semantics |

**Public catalog executor (`service_role` EXECUTE, catalog-executor
owner, `search_path = pg_catalog, public, extensions`)**

| Signature | Role |
|---|---|
| `insert_requirement_group_projection_threshold(requirement_group_projection_thresholds)` | DRAFT v0.2 `AT_LEAST` reviewer threshold; four non-`FULL` projections only |

013 `CREATE OR REPLACE public.create_taxonomy_release(text,timestamptz,text)`
keeps this same owner, `service_role` caller, and catalog `search_path`.
Its replacement body calls `public.allocate_taxonomy_release_ordinal_v02()`
and persists the returned ordinal. It does not name `private` objects.

008 identity-manifest writers remain 012
`insert_eligibility_manifest_*` and are reused for v0.2 BUILDING rows.
Reuse does not expand the decision mapping universe: v0.2 pin
obligation follows section 5.0, not “every manifest mapping ID.”

**Public taxonomy ordinal bridge (013 9B; `SECURITY DEFINER`; owned by
`foundation_migration_owner`; `search_path = pg_catalog, private`;
EXECUTE only `foundation_catalog_executor`)**

| Signature | Role |
|---|---|
| `public.allocate_taxonomy_release_ordinal_v02()` | allocate the next positive `release_ordinal` only; does not create, verify, or retire a release |

This is the sole catalog-executor path to the private allocator.
`foundation_catalog_executor` is the EXECUTE grantee, not the owner.
`service_role` has no EXECUTE. Section 7 is authoritative.

**Private invoker helpers (migration-owner; EXECUTE only to the named
executor, except the ordinal allocator as noted)**

| Signature | Caller |
|---|---|
| `private.canonical_eligibility_v02_input_fingerprint(uuid)` | evaluation executor |
| `private.canonical_eligibility_v02_result_fingerprint(uuid)` | evaluation executor |
| `private.canonical_json_v02(jsonb)` | fingerprint helpers |
| `private.eligibility_v02_leaf_class(requirement_strength, requirement_semantics)` | finalizer |
| `private.eligibility_v02_project_leaf(class, projection, actual)` | finalizer |
| `private.eligibility_v02_aggregate(operator, values[], k)` | finalizer |
| `private.eligibility_v02_derive_outcome(ordinary, conditional)` | finalizer |
| `private.eligibility_v02_active_at_ordinal(introduced, pin, retired)` | start/verify/finalize |
| `private.taxonomy_allocate_release_ordinal()` | `public.allocate_taxonomy_release_ordinal_v02` only (owner implicit EXECUTE; **not** catalog executor, **not** `service_role`) |

**CREATE OR REPLACE of named 012 signatures** — section 0 decision 6.

Installation uses remediation §3.1 choreography for every new 9B
SECURITY DEFINER signature **except**
`public.allocate_taxonomy_release_ordinal_v02()`, which uses the
section 7.2 ownership choreography and is **not** transferred to
`foundation_catalog_executor`. 013 does not create executor roles. It
`GRANT <executor> TO foundation_migration_owner WITH ADMIN OPTION` only if
the 012 grant already exists (it must). Temporary schema `CREATE` for
ownership transfer of catalog/student/evaluation 9B signatures is granted,
used, and revoked in the same transaction before post-install assertions.
Every 9B signature, including the ordinal bridge and
`private.taxonomy_allocate_release_ordinal()`, is inserted into
`foundation_function_contracts`. Replaced 012 signatures update
`body_digest` only; owner, callers, and `search_path` stay equal to the
012 registry row. `create_taxonomy_release` therefore keeps catalog-
executor owner, `service_role` caller, and
`pg_catalog, public, extensions`.

### 1.6 TypeScript / contract artifacts (not SQL)

- `packages/eligibility-engine/contracts/eligibility-v0.2.json`
- `packages/eligibility-engine/contracts/vectors/*.jsonl`
- `packages/eligibility-engine/scripts/generate-v02-registry.mjs`
- `packages/eligibility-engine/src/v02/` (`types.ts`, `evaluate.ts`,
  `canonicalize.ts`, `reasons.ts`, `index.ts`)
- `packages/eligibility-engine/test/v02/*.test.ts`

Existing `src/evaluate.ts`, `src/types.ts`, and v0.1 tests are not edited
in place except `src/index.ts` re-exports of the new `v02` module under
distinct names.

### 1.7 Objects 013 must not create

Fit tables, Fit evaluator package, Financial `billing_basis` objects,
generic policy DSL, capability registry, event-sourcing log, plugin
privacy hooks, a second student lock identity, or a sixth projection
enum value. 013 must not `GRANT USAGE ON SCHEMA private TO
foundation_catalog_executor`.

---

## 2. v0.1 / v0.2 coexistence model

### 2.1 Discriminator

The single discriminator is
`public.eligibility_evaluations.input_schema_version`.

| Path | Start | Seal | Finalize | `input_schema_version` | Rule-set contract |
|---|---|---|---|---|---|
| v0.1 historical | `start_eligibility_evaluation` | `seal_eligibility_evaluation_inputs` | `finalize_eligibility_evaluation(uuid, outcome)` | `eligibility-v0.1` | `phase2-v0.1` / `eligibility-v0.1` |
| v0.2 | `start_eligibility_evaluation_v02` | `seal_eligibility_evaluation_inputs_v02` | `finalize_eligibility_evaluation_v02(uuid)` | `eligibility-v0.2` | `phase2-v0.2` / `eligibility-v0.2` |

Cross calls fail `55000` with stable hints:

- `eligibility_v01_api_on_v02_row`
- `eligibility_v02_api_on_v01_row`
- `eligibility_v02_caller_outcome_forbidden` (there is no outcome argument)

v0.1 finalize continues to trust caller `outcome` **only** under the 008
root/outcome constraint. v0.2 finalize has no such argument and overwrites
any caller-inserted leaf/group truth: v0.2 rows reject caller inserts into
`eligibility_requirement_results`, `eligibility_course_matches`,
`eligibility_test_matches`, projection, and negative-authority tables
unless `private.eligibility_v02_finalize_authorizations` matches
`txid_current()`.

### 2.2 Historical byte-for-byte law

013 does not `UPDATE` existing v0.1 evaluation, manifest, result, match, or
`input_fingerprint` rows. 013 does not recompute v0.1 hashes. 013 does not
backfill synthetic pins onto v0.1 rows. Completed v0.1 evaluations remain
replayable under the v0.1 contract until privacy deletion.

### 2.3 Current-start vs replay

New v0.2 start requires **current** heads: profile `FROZEN`, rule set
`VERIFIED` with `eligibility-v0.2`, taxonomy release `VERIFIED`, every
referenced catalog mapping currently `VERIFIED`, every referenced
observation currently selected `KNOWN` with headed `REVIEWED_APPLICABLE`
applicability (012 law).

“`VERIFIED` at start” for a mapping means `VERIFIED` at the controlled
mapping-pin boundary under the student lifecycle lock and source-row
`FOR KEY SHARE` (section 6.2), not an earlier unlocked read. A mapping
that is `REJECTED` or already `RETIRED` at that boundary is outside the
decision universe: no pin is created.

Start is not itself a multi-transaction snapshot of every later assembly
row. Each pin becomes authoritative only when its insert function locks and
copies the source row (section 6.2). Therefore a live object changed between
start and its pin insert is observed in the changed state and the pin insert
fails if that state is no longer eligible. Once the pin exists, later live
changes cannot reinterpret it. Seal/finalize validate pins and set equality
and **do not** re-read `source_identities.current_source_id`,
`evidence_applicability_heads`, `canonical_field_selections`, live
`mapping_status`, or live `retired_release_ordinal`. Retirement after the
relevant pin insert cannot reinterpret a sealed/completed v0.2 evaluation
(`status_at_pin` remains `VERIFIED`). A **new** start cannot use the
retired object.

---

## 3. Domain snapshot schema

### 3.1 Scope kinds (first-class; NULL is executable)

`eligibility_snapshot_scopes` is the only completeness/membership identity.
Ordinary SQL `NULL = NULL` is never used as semantic equality. Uniqueness
is `NULLS NOT DISTINCT`.

| `scope_kind` | `education_context_id` | Allowed `domain` | Members |
|---|---|---|---|
| `GLOBAL_PROFILE` | MUST be NULL | `EDUCATION_HISTORY`, `TEST_HISTORY`, `EXPERIENCE_HISTORY`, `SKILL_HISTORY`, `PREFERENCES`, `GOALS` | degrees only on `EDUCATION_HISTORY`; tests only on `TEST_HISTORY`; no courses |
| `EDUCATION_CONTEXT` | MUST be a `student_degrees.student_degree_id` of this profile | `COURSE_HISTORY`, `COURSE_MAPPING` | courses with that `student_degree_id`; course mappings of those courses |
| `UNASSIGNED_CONTEXT` | MUST be NULL | `COURSE_HISTORY`, `COURSE_MAPPING` | courses with `student_degree_id IS NULL`; mappings of those courses |

Illegal combinations fail insert (`22023`, hint
`eligibility_snapshot_scope_shape`):

- `GLOBAL_PROFILE` with non-null context;
- `EDUCATION_CONTEXT` with null context, or a degree from another profile;
- `UNASSIGNED_CONTEXT` with non-null context;
- `COURSE_HISTORY` / `COURSE_MAPPING` on `GLOBAL_PROFILE`;
- `EDUCATION_HISTORY` / `TEST_HISTORY` on an education or unassigned scope.

**`UNASSIGNED_CONTEXT` always exists as a snapshot scope** for both
`COURSE_HISTORY` and `COURSE_MAPPING`, even when empty. It replaces v0.1
“global course scope only when there are no degrees.” A profile with
degrees still has unassigned snapshot scopes. Omitting them fails seal.
It is **not** a new Phase 2 completeness identity (section 3.4).

### 3.2 Closed partition of records

Seal reconstructs expected membership from the frozen profile (not from
caller choice) and requires bidirectional `EXCEPT` emptiness:

| Record | Expected scope |
|---|---|
| every `student_degrees` row of the profile | `GLOBAL_PROFILE` / `EDUCATION_HISTORY` |
| every course with non-null `student_degree_id` | that degree’s `EDUCATION_CONTEXT` / `COURSE_HISTORY` |
| every course with null `student_degree_id` | `UNASSIGNED_CONTEXT` / `COURSE_HISTORY` |
| every `student_test_scores` row | `GLOBAL_PROFILE` / `TEST_HISTORY` |
| every **universe-eligible** student mapping (`VERIFIED`, or contract-relevant `PROPOSED`) with `record_type = COURSE` whose course has a degree | that degree’s `EDUCATION_CONTEXT` / `COURSE_MAPPING` |
| every **universe-eligible** student mapping with `record_type = COURSE` whose course is unassigned | `UNASSIGNED_CONTEXT` / `COURSE_MAPPING` |
| every **universe-eligible** student mapping with `record_type = DEGREE` | `GLOBAL_PROFILE` / `EDUCATION_HISTORY` mapping universe |

`REJECTED` and already-`RETIRED` mappings at the pin boundary are not
snapshot members and are not partitioned here. They remain upstream
history only (section 5.0).

No record belongs to two scopes. A null-context course parked on an
`EDUCATION_CONTEXT` fails. A degree-linked course parked on
`UNASSIGNED_CONTEXT` fails. A wrong-profile ID fails the manifest FK and
the equality check.

### 3.3 Completeness authority

Every `student_data_completeness` row of the frozen profile has exactly one
`eligibility_completeness_pins` row (`completeness_id` equality plus copied
`domain` / `completeness` / `explanation` / `education_context_id`).
Bidirectional equality:

- profile completeness IDs ↔ completeness pins;
- 008 `eligibility_manifest_completeness` ↔ completeness pins;
- snapshot scopes bind a `completeness_id` **only** when that pin is the
  012-required completeness identity for that scope (section 3.4).
- completeness-pin `scope_id` may be NULL when the upstream completeness
  row has no 012 applicability scope; do not fabricate a scope.

Missing, extra, wrong-domain, or wrong-context completeness **pins**
(versus the frozen-profile completeness set) fail seal
(`55000`, `eligibility_completeness_universe_mismatch`).

`PARTIAL` and `UNKNOWN` completeness are valid pin values. They never
authorize `NOT_SATISFIED` (section 4). Completeness is never inferred
`COMPLETE` from the existence of other completeness rows.

### 3.4 `UNASSIGNED_CONTEXT` law (inspected 012 freeze)

013 **does not** modify `freeze_student_profile_version()`.

Inspected 012 freeze `required_scope` in
`202608200012_frozen_foundation_critical_hardening.sql` (identical
membership to 005 `guard_student_profile_version`):

| 012 required completeness | When |
|---|---|
| `(education_context_id IS NULL, domain)` for `EDUCATION_HISTORY`, `TEST_HISTORY`, `EXPERIENCE_HISTORY`, `SKILL_HISTORY`, `PREFERENCES`, `GOALS` | always |
| `(education_context_id = student_degree_id, COURSE_HISTORY)` and same for `COURSE_MAPPING` | each degree of the profile |
| `(education_context_id IS NULL, COURSE_HISTORY)` and same for `COURSE_MAPPING` | **only if the profile has zero degrees** |

`student_test_scores` have no education-context FK. They remain
`GLOBAL_PROFILE` / `TEST_HISTORY` members. 012 always requires that
NULL-context `TEST_HISTORY` completeness. `UNASSIGNED_CONTEXT` never
owns `TEST_HISTORY`.

`UNASSIGNED_CONTEXT` snapshot membership (closed-world, bidirectional
`EXCEPT` emptiness; omit or extra fails seal/finalize
`eligibility_course_universe_mismatch` /
`eligibility_authoritative_universe_mismatch`):

| Frozen-profile record | Snapshot |
|---|---|
| every `student_courses` row with `student_degree_id IS NULL` | `UNASSIGNED_CONTEXT` / `COURSE_HISTORY` |
| every **universe-eligible** student mapping with `record_type = COURSE` whose course has `student_degree_id IS NULL` | `UNASSIGNED_CONTEXT` / `COURSE_MAPPING` |

Do not fabricate a completeness row for those records. Do not treat an
optional extra NULL-context `COURSE_*` completeness row on a profile
that has degrees as 012 authority (that would invent a completeness
identity freeze does not require).

**Which 012 scope may authorize an `UNASSIGNED_CONTEXT` negative:**

- **Zero-degree profile:** the 012-required NULL-context `COURSE_HISTORY`
  and `COURSE_MAPPING` completeness rows. Those pins attach to the
  `UNASSIGNED_CONTEXT` snapshot scopes. If both are `COMPLETE` and
  section 4.2 otherwise holds, course-absence `NOT_SATISFIED` is
  allowed.
- **Profile with one or more degrees:** **no 012 scope safely covers
  `UNASSIGNED_CONTEXT`.** Per-degree `COURSE_*` completeness covers only
  that degree’s courses. Global `EDUCATION_HISTORY` / `TEST_HISTORY` do
  not cover courses. Separate per-degree completeness rows do **not**
  authorize unassigned absence. 013 fails closed: `UNASSIGNED_CONTEXT`
  `completeness_id` and `completeness` are NULL; no negative proof may
  use this scope. Absence over `UNASSIGNED_CONTEXT` remains
  `UNASSIGNED_CONTEXT_COMPLETENESS_UNAVAILABLE`.

Positive use of pinned NULL-context records is always allowed. Absence
of a satisfying NULL-context record cannot establish `NOT_SATISFIED`
without the zero-degree 012 authority above.

### 3.5 008 identity manifests still exist

v0.2 reuses `eligibility_manifest_degrees`, `_courses`, `_test_scores`,
`_student_mappings`, `_student_evidence`, `_catalog_sources`,
`_catalog_mappings`, `_taxonomy_concepts`. Seal requires:

```text
degree/course/test manifest IDs = snapshot member IDs = profile IDs
required evaluation mapping universe
  = in-scope VERIFIED mapping IDs
    + contract-relevant in-scope PROPOSED mapping IDs
mapping pins = that same required universe
mapping-universe IDs = those pins, partitioned by status and scope
  VERIFIED → AUTHORITATIVE; PROPOSED → LIMITING
```

in both directions for each applicable family. This is **not** “every
student mapping ID of the profile.” `REJECTED` and already-`RETIRED`
mappings at the pin boundary are excluded from **both** sides: no pin,
no universe row, no identity-only pin, no seal failure if they are
omitted from the identity manifest. Extra unrelated `VERIFIED` mappings
or extra out-of-scope `PROPOSED` mappings fail. Omitted in-scope
`VERIFIED` mappings fail. Omitted contract-relevant in-scope `PROPOSED`
mappings fail (section 5.1, tests M4–M5).

---

## 4. Negative-authority schema

### 4.1 Tables

`eligibility_negative_fact_authorizations` and
`eligibility_negative_authorization_scopes` (section 1.4). Inserted only by
`finalize_eligibility_evaluation_v02`. No public insert function.

A v0.2 `NOT_SATISFIED` leaf is illegal unless the finalizer also inserts
exactly one authorization row for that `rule_node_id` whose child scope set
equals the proof’s required scopes (bidirectional `EXCEPT`). Caller reason
text cannot create absence.

### 4.2 Proof obligations (closed, fail-closed)

**Course absence (`HAS_COURSE_CONCEPT` → `NOT_SATISFIED`)** requires all of:

1. every `EDUCATION_CONTEXT` is `COMPLETE` for both `COURSE_HISTORY` and
   `COURSE_MAPPING`;
2. `UNASSIGNED_CONTEXT` has 012 completeness authority (zero-degree
   profile; section 3.4) and that authority is `COMPLETE` for both
   `COURSE_HISTORY` and `COURSE_MAPPING`. If the profile has degrees,
   this conjunct **fails** and the leaf cannot be `NOT_SATISFIED`;
3. degree/course/mapping equalities in section 3 hold;
4. no in-scope `COMPLETED` course has an **authoritative** mapping to the
   pinned target concept;
5. no **limiting** (`PROPOSED`) mapping to that target concept exists in
   those scopes;
6. pinned catalog mapping for the node is `status_at_pin = VERIFIED` with
   `relation_at_pin = COURSE_EQUIVALENCY` (otherwise the leaf is `UNKNOWN`,
   not a negative proof);
7. target concept is active at the pinned ordinal.

Authorization scopes = every `COURSE_HISTORY` and `COURSE_MAPPING` scope
of kind `EDUCATION_CONTEXT`, plus `UNASSIGNED_CONTEXT` **only** when
section 3.4 attached 012 completeness authority.

When the profile has degrees and no satisfying authoritative path exists,
the leaf is `UNKNOWN` with
`UNASSIGNED_CONTEXT_COMPLETENESS_UNAVAILABLE`. Empty unassigned
membership is not a substitute for that authority.

**Test absence (`HAS_TEST` → `NOT_SATISFIED`)** requires:

1. `GLOBAL_PROFILE` / `TEST_HISTORY` is `COMPLETE`;
2. exact test-set equality;
3. no pinned test with `assessment_concept_id = target_concept_id`.

Authorization scopes = that single test-history scope.

**Degree-side mapping absence** is not a leaf in v0.2. v0.2 does not
introduce `HAS_DEGREE` or any degree-absence negative predicate. Degree
snapshot equality is still required so course contexts cannot be
fabricated.

### 4.3 Completeness → truth

| Completeness on a required scope | Absence conclusion |
|---|---|
| `COMPLETE` on every required scope **including** 012-authorized `UNASSIGNED_CONTEXT` when it exists, equalities hold, no satisfying path, no limiting proposal | `NOT_SATISFIED` + authorization row |
| any required scope `PARTIAL` or `UNKNOWN` | `UNKNOWN`; no authorization row |
| `UNASSIGNED_CONTEXT` lacks 012 completeness authority (profile has degrees) | `UNKNOWN` (`UNASSIGNED_CONTEXT_COMPLETENESS_UNAVAILABLE`); no authorization row; pinned satisfying unassigned courses may still yield `SATISFIED` |
| any required scope omitted | seal/finalize fails; no truth is stored |
| equalities fail | seal/finalize fails |

Missing completeness is not coerced to `NOT_SATISFIED`. Absence over
NULL-context courses is not coerced to `NOT_SATISFIED` without the
section 3.4 012 authority.

### 4.4 Mapping authority inside a negative proof

- `VERIFIED` (`status_at_pin`) + allowed relation + in-scope record +
  active concept + evidence in manifest → **authoritative**. May satisfy.
  If a satisfying authoritative mapping exists, the leaf is `SATISFIED`,
  not negative. In-scope `VERIFIED` mappings MUST be pinned (section 5.0).
- `PROPOSED` + same target-concept space + in-scope record → **limiting**.
  Pin only when the contract treats the proposal as limiting evidence.
  Cannot satisfy. Blocks `NOT_SATISFIED` and yields `UNKNOWN`.
- `REJECTED` and already-`RETIRED` at the pin boundary → **outside the
  decision universe**. MUST NOT create a pin. MUST NOT satisfy. MUST NOT
  independently create `UNKNOWN`. MUST NOT receive an AUTHORITATIVE or
  LIMITING universe row (`22023`,
  `eligibility_mapping_status_not_universe_eligible`). They remain
  upstream history only. There is no identity-only pin and no
  `status_at_pin` of those values. Live retirement **after** a
  `VERIFIED` pin insert is irrelevant: the pin stays `VERIFIED`.

---

## 5. Mapping-universe definition

### 5.0 Authoritative mapping pin law (sole identity)

Eligibility v0.2 pins mappings according to their normative status **at
the evaluation pin / start boundary** (the locked pin-insert copy in
section 6.2). The decision mapping universe is **not** the set of every
historical mapping row owned by the profile. It contains only mappings
that are semantically relevant to this evaluation.

```text
required evaluation mapping universe
  = in-scope VERIFIED mappings
    + contract-relevant in-scope PROPOSED mappings
```

`REJECTED` and already-`RETIRED` mappings are excluded from **both**
sides. Do not create identity-only pin rows for them.

1. **`VERIFIED` at pin time.** MUST be included when in scope for an
   evaluated student or catalog record. MUST create an immutable
   evaluation-scoped mapping pin. Pin at minimum: mapping ID,
   `status_at_pin = VERIFIED`, `relation_at_pin`, `concept_id` (copied
   at pin), review identity/evidence at pin, retirement state at pin,
   source record identity. It is authoritative and may satisfy a
   predicate only when the relation is authorized by the rule/method
   contract. Omitting an in-scope `VERIFIED` mapping fails closed-world
   equality / finalization.
2. **`PROPOSED` at pin time.** May be included only where the v0.2
   contract treats a proposal as limiting evidence. When relevant to
   the evaluated predicate/universe, pin it with
   `status_at_pin = PROPOSED`. It MUST NOT satisfy a requirement. It
   may prevent an unjustified negative conclusion and cause `UNKNOWN`
   where the contract requires.
3. **`REJECTED` at pin time.** Outside the decision mapping universe.
   MUST NOT create an evaluation mapping pin. MUST NOT satisfy. MUST
   NOT independently create `UNKNOWN`. Its historical database row
   remains upstream history only.
4. **Already `RETIRED` at pin time.** Same as `REJECTED`: outside the
   universe, no pin, no satisfaction. Historical row remains upstream
   history only.
5. **Later retirement.** If a mapping is `VERIFIED` at pin time, it is
   pinned with `status_at_pin = VERIFIED`. A later live change to
   `RETIRED` does not mutate the pin. Completed and in-flight v0.2
   evaluations continue to use the immutable pin. Later live retirement
   MUST NOT invalidate match insertion, finalization, or replay.

Replay uses `status_at_pin` only.

```text
T0 mapping = VERIFIED
T1 evaluation pins mapping as VERIFIED
T2 live mapping becomes RETIRED
T3 evaluation finalizes / replays
  → v0.2 remains valid using the T1 pin

T0 mapping already = RETIRED  → T1 start creates no mapping pin
T0 mapping = REJECTED        → T1 start creates no mapping pin
```

Closed-world validation still rejects: omitted in-scope `VERIFIED`;
extra unrelated `VERIFIED`; omitted relevant `PROPOSED` where the
contract requires limiting evidence; extra out-of-scope `PROPOSED`;
wrong mapping relation / concept / source; fabricated `status_at_pin`.

### 5.1 Student universes (from pins, never live heads)

For each mapping snapshot scope:

- **AUTHORITATIVE** = pinned student mappings with
  `status_at_pin = VERIFIED`,
  `relation_at_pin = STUDENT_CONCEPT_ASSOCIATION`, mapped record a member
  of that scope, concept pin active at
  `eligibility_rule_set_pins.taxonomy_release_ordinal`, and
  `student_evidence_id` in `eligibility_manifest_student_evidence`.
- **LIMITING** = pinned student mappings with
  `status_at_pin = PROPOSED`, same record-set and taxonomy-valid concept
  filter, and only when the contract treats that proposal as limiting
  evidence.
- `REJECTED` / already-`RETIRED` at the pin boundary are **not pinned**
  and appear in neither universe. They are not a third “NO-AUTHORITY
  pin set.”

Seal/finalize require bidirectional `EXCEPT` emptiness:

```text
required evaluation mapping universe
  = in-scope VERIFIED + contract-relevant in-scope PROPOSED
PINNED set
  = that required universe, each with copied pin state
    status_at_pin IN (VERIFIED, PROPOSED) only
AUTHORITATIVE universe
  = pins where status_at_pin = VERIFIED, restricted to that scope
LIMITING universe
  = pins where status_at_pin = PROPOSED, restricted to that scope
REJECTED / already-RETIRED
  = excluded from both sides; no pin; no universe row
```

Consequences:

- omitted in-scope `VERIFIED` mapping → sets unequal → **finalization
  fails** (`55000`, `eligibility_authoritative_universe_mismatch`); it
  is not silently treated as absence;
- extra unrelated `VERIFIED` mapping in universe or pins → **fails**;
- omitted contract-relevant in-scope `PROPOSED` → **fails** (or the
  contract-defined `UNKNOWN` limiting proof cannot be formed);
- extra out-of-scope `PROPOSED` → **fails**;
- swapping `VERIFIED` into LIMITING or `PROPOSED` into AUTHORITATIVE →
  **fails**;
- omitted `REJECTED` / already-`RETIRED` historical row → **does not
  fail**; those rows are not required identity;
- pin insert with `status_at_pin IN (REJECTED, RETIRED)`, or a
  fabricated `VERIFIED` pin for a mapping that was `PROPOSED`,
  `REJECTED`, or `RETIRED` at the pin boundary → **fails**
  (`eligibility_mapping_status_not_universe_eligible` or
  `eligibility_pin_payload_mismatch`).

### 5.2 Catalog universes

Analogous partition over `eligibility_catalog_mapping_pins` versus
the required catalog decision universe (not every
`eligibility_manifest_catalog_mappings` historical row) and
`eligibility_rule_node_mapping_pins`. Catalog `REJECTED` /
already-`RETIRED` mappings at the pin boundary are not pinned.

Allowed `relation_at_pin` for `HAS_COURSE_CONCEPT`:
`COURSE_EQUIVALENCY` only. Other catalog relations may be pinned only if
the verified rule node references them; v0.2 verification rejects a course
predicate whose node mapping is not `COURSE_EQUIVALENCY`.

### 5.3 Pin-at-use fields (no live-head replay)

Copied at insert, under the student lifecycle lock, from the row that
exists at that moment. Pins are created only for section 5.0 universe
members (`status_at_pin IN (VERIFIED, PROPOSED)`).

| Identity | Pin columns |
|---|---|
| mapping ID | `catalog_mapping_id` / `student_mapping_id` (immutable FK) |
| status at use | `status_at_pin` (`VERIFIED` or `PROPOSED` only) |
| relation at use | `relation_at_pin` |
| concept ID at pin | `concept_id` (copied; not a live-head reread) |
| review authority | `reviewed_by`, `reviewed_at`, `method`, `confidence`, `model_version` |
| review evidence | `verification_evidence_id` or `student_evidence_id` |
| source record identity | `record_type`, `record_id` / `student_record_id`, `profile_version_id` |
| retirement state at pin | `retired_at_pin`, `retirement_reason_at_pin` (the state observed at pin time; null while the then-live status is `VERIFIED` or `PROPOSED`) |

`status_at_pin IN (REJECTED, RETIRED)` is illegal on insert. There is
no identity-only pin for those statuses. Replay reads only these
copies. Live `mapping_status` after the pin insert is not consulted.

### 5.4 008 match-insert validator (authorized 013 `CREATE OR REPLACE`)

Inspected `202608200008_eligibility_persistence.sql`:

| 008 object | Identity 013 keeps |
|---|---|
| function `public.validate_eligibility_match_insert()` | same name; 013 `CREATE OR REPLACE` |
| trigger `eligibility_course_matches_validate` `BEFORE INSERT` on `public.eligibility_course_matches` | same trigger name, table, timing, `execute function public.validate_eligibility_match_insert()` |
| trigger `eligibility_test_matches_validate` `BEFORE INSERT` on `public.eligibility_test_matches` | same trigger name, table, timing, `execute function public.validate_eligibility_match_insert()` |

012 does not replace this function and does not list it in
`foundation_function_contracts`. 013 does not edit migration 008.
This is an additive compatibility override listed in section 0 decision 6.
013 inserts the replaced signature into `foundation_function_contracts`.

Replacement body branches on the owning evaluation
`input_schema_version`. `search_path` on the replaced SECURITY DEFINER
function becomes the 012 trusted evaluation path
`pg_catalog, public, private, extensions` (no `pg_temp`).

**v0.1 branch (`input_schema_version = 'eligibility-v0.1'`):** preserve
the 008 live checks exactly:

- course matches require a `SATISFIED` `HAS_COURSE_CONCEPT` result;
- live `catalog_concept_mappings.mapping_status = 'VERIFIED'`;
- live `student_record_concept_mappings.mapping_status = 'VERIFIED'`;
- live catalog and student `concept_id` equal the node
  `target_concept_id`;
- live student mapping `student_record_id` equals the matched course;
- live `student_courses.course_status = 'COMPLETED'` with matching
  evidence;
- test matches require a `SATISFIED` `HAS_TEST` result and live
  `assessment_concept_id = target_concept_id`.

A currently `RETIRED` live mapping still fails v0.1 insert, as in 008.

**v0.2 branch (`input_schema_version = 'eligibility-v0.2'`):** do **not**
read live `mapping_status`. The match must reference the exact
evaluation-scoped pins. Validate:

- mapping ID at use: `catalog_mapping_id` /
  `student_mapping_id` exist in `eligibility_catalog_mapping_pins` /
  `eligibility_student_mapping_pins` for this `evaluation_id`;
- `status_at_pin = VERIFIED` on both pins;
- `relation_at_pin`: catalog `COURSE_EQUIVALENCY`; student
  `STUDENT_CONCEPT_ASSOCIATION`;
- `concept_id` on both pins equals the pinned node `target_concept_id`;
- review / evidence at pin: catalog
  `verification_evidence_id`, `reviewed_by`, `reviewed_at`; student
  `student_evidence_id`, `reviewed_by`, `reviewed_at`; course match
  evidence equals the pinned student-mapping evidence and the frozen
  course evidence;
- rule / evaluation ownership: result row belongs to this evaluation;
  node belongs to the pinned rule set; matched course / test is a
  snapshot member.

Later live `RETIRED` / changed `mapping_status` must not invalidate
v0.2 insert or finalization. Current live status is irrelevant after
pinning. Caller cannot fabricate a `VERIFIED` pin from a mapping that
was `PROPOSED`, `REJECTED`, or `RETIRED` at the pin boundary
(section 6.2). A mapping already `REJECTED` or `RETIRED` at that
boundary has no pin, so it cannot satisfy a v0.2 match.

---

## 6. Replay-pin model

### 6.1 Strategy table (executable)

| Required identity | Table.column | Strategy |
|---|---|---|
| Profile version / hash | `eligibility_evaluations.profile_version_id`, `profile_snapshot_hash` | Copied at start from frozen profile. Replay does not re-hash the live profile. |
| Completeness | `eligibility_completeness_pins.*` | FK + copied scalars. |
| Education-context scope | `eligibility_snapshot_scopes.scope_id`, `scope_kind`, `education_context_id` | First-class snapshot identity. |
| Courses / degrees / tests | 008 manifests + snapshot membership | Frozen-profile FKs; scalars for canonicalization read from frozen fact rows (immutable after freeze) plus membership pins. |
| Student mappings | `eligibility_student_mapping_pins` | Pin-at-use copies. |
| Catalog mappings | `eligibility_catalog_mapping_pins` + `eligibility_rule_node_mapping_pins` | Pin-at-use copies. |
| Taxonomy concepts | `eligibility_taxonomy_concept_pins` | Pin-at-use ordinals. |
| Rule set / version | `eligibility_rule_set_pins` | FK + copied versions. |
| Requirement nodes | `eligibility_rule_node_pins` | Full tree copy. |
| Projection thresholds | `eligibility_projection_threshold_pins` | Copy of verified `requirement_group_projection_thresholds` identity and value. |
| Canonical observation | `eligibility_rule_node_source_pins.field_observation_id` | Immutable FK. |
| Observation scalars / source revision | `eligibility_catalog_observation_pins` | Copies `sources.source_id` (revision), `source_identity_id`, `revision_number`, `retrieval_content_hash`. **Never** `current_source_id`. |
| Canonical selection at use | `eligibility_catalog_selection_pins` | Pin-at-use; replay does not read `canonical_field_selections`. |
| Applicability assertion | `eligibility_rule_node_source_pins.applicability_assertion_id` | Immutable FK. |
| Applicability head at pin | `applicability_head_assertion_id_at_pin` | UUID copy; must equal `applicability_assertion_id`. Replay does not read `evidence_applicability_heads`. |
| Applicability scope | `applicability_scope_id` + `knowledge_status_at_pin` | Immutable FK + copy. |
| Taxonomy release ordinal | `eligibility_rule_set_pins.taxonomy_release_ordinal` and `eligibility_evaluations.taxonomy_release_ordinal` | Pin-at-use bigint. Must match. |
| Engine/schema/contract | evaluation columns + rule-set pin | Copied at start. |
| Evaluator name/version/build | `eligibility_evaluations.evaluator_*` | Copied at start. |

### 6.2 Insert-time copy rule

Each `insert_eligibility_*_pin` function, after the student lock:

1. requires the evaluation `BUILDING`, unsealed, `eligibility-v0.2`;
2. reads the source row `FOR KEY SHARE`;
3. copies listed scalars from that row (caller-supplied pin fields that
   disagree with the source row fail `22023`,
   `eligibility_pin_payload_mismatch`);
4. inserts the pin;
5. writes `private.student_lifecycle_audit`.

Caller cannot invent a `VERIFIED` status for a live `PROPOSED`,
`REJECTED`, or `RETIRED` mapping. A source row whose live
`mapping_status` is `REJECTED` or `RETIRED` at this locked boundary
MUST NOT receive a pin (`eligibility_mapping_status_not_universe_eligible`).

`SELECT … FOR KEY SHARE` / `FOR UPDATE` applies UPDATE RLS `USING`
expressions in addition to table `UPDATE` privilege. 013 therefore grants
`foundation_evaluation_executor` `SELECT, UPDATE` on locked source tables
and adds lock-visibility policies
`USING (current_user = 'foundation_evaluation_executor')` for `SELECT`
and the same `USING` with `WITH CHECK (false)` for `UPDATE`. Direct
`UPDATE` DML fails (`44000`); start/pin/finalize locks succeed. This is
not mutation authority and does not amend 012 D-USAGE.

### 6.3 Current heads at start only

`start_eligibility_evaluation_v02` checks current `VERIFIED` / selected
`KNOWN` / `REVIEWED_APPLICABLE` / taxonomy `VERIFIED` as 008/012 start
already does, plus ordinal membership
`private.eligibility_v02_active_at_ordinal`. “Current `VERIFIED`” for a
mapping is the locked pin-boundary observation (section 2.3 / 6.2), not
an earlier unlocked read. After pinning, only pins matter. Replay uses
`status_at_pin` only.

---

## 7. Taxonomy ordinal model

### 7.1 One law

012 remains owner of taxonomy **lifecycle** (`DRAFT → VERIFIED → RETIRED`,
direct-DML denial, text `introduced_in_release` / `retired_in_release`).
013 owns **ordinals**. 012 tests must not require ordinal columns.

Frozen 012 D-USAGE is not amended: after 013,
`has_schema_privilege('foundation_catalog_executor', 'private', 'USAGE')`
is false. `create_taxonomy_release` remains owned by
`foundation_catalog_executor` with
`search_path = pg_catalog, public, extensions`. It therefore never names
`private` objects, never calls
`private.taxonomy_allocate_release_ordinal()`, and never reads or writes
`private.taxonomy_release_ordinal_allocator`.

013 installs one narrow public SECURITY DEFINER ordinal bridge. That
bridge is the only authorized path from the catalog executor to the
private allocator.

### 7.2 Wrapper identity, ownership, and installation

**013 registry identity (required before implementation):**

`public.allocate_taxonomy_release_ordinal_v02()`

Zero arguments. Returns `bigint`. Name follows the 013 `_v02` public-
entry convention (`start_eligibility_evaluation_v02`,
`finalize_eligibility_evaluation_v02`).

| Attribute | Contract |
|---|---|
| Schema | `public` |
| Identity arguments | none (`pg_get_function_identity_arguments` is empty) |
| Return | `bigint` — the newly allocated positive ordinal only (`>= 1`) |
| `prosecdef` | true (`SECURITY DEFINER`) |
| Owner | `foundation_migration_owner` — the 013 install authority (`current_user` of 013; owner of schemas `public` and `private` after 012). **Not** `foundation_catalog_executor`. **Not** `service_role`. 013 does not create a dedicated ordinal executor role. |
| `search_path` | `pg_catalog, private` (function `SET search_path`; immutable; no `pg_temp`; no caller path; no `extensions`; `public` omitted because the body only schema-qualifies the private allocator) |
| EXECUTE | `REVOKE ALL` from `PUBLIC`, `anon`, `authenticated`, `service_role`, `authenticator`. `GRANT EXECUTE` only to `foundation_catalog_executor`. No extra GRANT to the install role (owner EXECUTE is implicit). |
| Capability | ordinal allocation only |

**Call chain (the only runtime path):**

```text
runtime authorized caller (service_role)
  → public.create_taxonomy_release(text, timestamptz, text)
       [SECURITY DEFINER / foundation_catalog_executor
        search_path = pg_catalog, public, extensions]
  → public.allocate_taxonomy_release_ordinal_v02()
       [SECURITY DEFINER / foundation_migration_owner
        search_path = pg_catalog, private]
  → private.taxonomy_allocate_release_ordinal()
       [SECURITY INVOKER / foundation_migration_owner
        search_path = pg_catalog, public, private]
  → private.taxonomy_release_ordinal_allocator
       (singleton row FOR UPDATE)
```

`create_taxonomy_release` then inserts `DRAFT` with the returned
immutable `release_ordinal` and locks that release row `FOR UPDATE`.

Wrapper body is exactly `RETURN private.taxonomy_allocate_release_ordinal();`
and nothing else. It does not create, verify, or retire a release; does
not accept a caller-supplied ordinal or any other argument; does not
accept schema/table/function identifiers; does not return allocator
internals or private rows; and does not `INSERT`/`UPDATE`/`DELETE` any
object other than by calling the private allocator.

**Ownership installation choreography** (012 §3.1 adapted for this
wrapper; other 9B catalog/student/evaluation signatures still use full
§3.1 `ALTER FUNCTION ... OWNER TO` the matching executor):

1. Do not `GRANT USAGE ON SCHEMA private TO foundation_catalog_executor`.
   Do not amend 012 D-USAGE.
2. As `foundation_migration_owner`, create
   `private.taxonomy_release_ordinal_allocator` and
   `private.taxonomy_allocate_release_ordinal()`. Direct runtime DML on
   the allocator table is revoked from `PUBLIC`, `anon`,
   `authenticated`, `service_role`, and all three 012 executors.
   Do not attach a catalog-executor SELECT policy on the allocator
   table.
3. Immediately `REVOKE ALL ON FUNCTION
   private.taxonomy_allocate_release_ordinal() FROM PUBLIC, anon,
   authenticated, service_role, authenticator,
   foundation_catalog_executor, foundation_student_executor,
   foundation_evaluation_executor`. No `GRANT EXECUTE` to any runtime
   or 012 executor. Owner EXECUTE is implicit.
4. Temporary `GRANT CREATE ON SCHEMA public TO
   foundation_catalog_executor` is **not** used for this wrapper.
   PostgreSQL requires schema `CREATE` on the new owner before
   `ALTER FUNCTION ... OWNER TO` succeeds; that transfer is forbidden
   here, so the temporary CREATE grant of §3.1 steps 4/8 is not
   opened for the wrapper. Other 9B catalog signatures still use
   that temporary CREATE/ALTER OWNER/revoke cycle in the same
   transaction.
5. As `foundation_migration_owner`, `CREATE FUNCTION
   public.allocate_taxonomy_release_ordinal_v02() RETURNS bigint
   LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog,
   private`.
6. Immediately `REVOKE ALL ON FUNCTION
   public.allocate_taxonomy_release_ordinal_v02() FROM PUBLIC, anon,
   authenticated, service_role, authenticator`.
7. Do **not** `ALTER FUNCTION public.allocate_taxonomy_release_ordinal_v02()
   OWNER TO foundation_catalog_executor`. Do **not** `ALTER FUNCTION
   ... OWNER TO service_role`. Ownership remains
   `foundation_migration_owner`. (012-style `ALTER FUNCTION OWNER TO`
   remains the install method for catalog/student/evaluation 9B
   entry points; applying it to this wrapper would make the DEFINER
   identity a role whose `USAGE` on `private` is false.)
8. `GRANT EXECUTE ON FUNCTION public.allocate_taxonomy_release_ordinal_v02()
   TO foundation_catalog_executor` only.
9. After all 013 ownership transfers, `REVOKE CREATE ON SCHEMA public
   / private / extensions` from the three 012 executors as in 012
   step 8. Retain catalog-executor `USAGE` on `public` and
   `extensions` only.
10. Run the post-install assertions below in the same transaction.
    Any violation aborts 013.

**Post-install assertions** (all must hold before commit):

- `has_schema_privilege('foundation_catalog_executor', 'private', 'USAGE')`
  is false (012 D-USAGE reaffirmed; 013 does not rewrite the 012
  assertion text).
- Wrapper `proowner` equals the `private` schema owner
  (`foundation_migration_owner`); not `foundation_catalog_executor`;
  not `service_role`.
- Wrapper `prosecdef` is true.
- Wrapper `proconfig` search_path is exactly `pg_catalog, private`
  (no `pg_temp`, no caller path).
- `has_function_privilege(role, 'public.allocate_taxonomy_release_ordinal_v02()',
  'EXECUTE')` is true only for `foundation_catalog_executor` among
  `{PUBLIC, anon, authenticated, service_role, authenticator,
  foundation_catalog_executor, foundation_student_executor,
  foundation_evaluation_executor}`.
- `has_function_privilege` of those same roles on
  `private.taxonomy_allocate_release_ordinal()` is false (owner
  implicit EXECUTE is not a `has_function_privilege` grant to those
  roles).
- `create_taxonomy_release(text,timestamptz,text)` owner remains
  `foundation_catalog_executor`; its search_path remains
  `pg_catalog, public, extensions`.
- Catalog executor has no table `SELECT`/`INSERT`/`UPDATE`/`DELETE` on
  `private.taxonomy_release_ordinal_allocator`.
- `foundation_function_contracts` contains both signatures with the
  owner, `prosecdef`, search_path, and `allowed_caller_roles` in this
  section (`{foundation_catalog_executor}` for the wrapper; empty
  caller array for the private allocator).

### 7.3 Allocator algorithm

`private.taxonomy_release_ordinal_allocator` is the singleton
authoritative allocator state. The correctness boundary is `FOR UPDATE`
of that row, not an advisory hash and not an unlocked
`SELECT max(release_ordinal) + 1`.

The private function is the only implementation of allocation. The
public wrapper performs no algorithm of its own. Neither function
accepts arguments.

Exact algorithm inside `private.taxonomy_allocate_release_ordinal()`,
executed while the outer `create_taxonomy_release` transaction is open:

1. `SELECT next_ordinal FROM private.taxonomy_release_ordinal_allocator
   WHERE singleton IS TRUE FOR UPDATE;`
   This row lock is held until the outer transaction commits or rolls
   back. Concurrent creators serialize here.
2. `allocated := GREATEST(
     next_ordinal,
     (SELECT COALESCE(MAX(release_ordinal), 0) + 1
      FROM public.taxonomy_releases)
   );`
   The `MAX+1` read is a post-lock verification against committed and
   this-transaction release rows. It is not a substitute for step 1.
   Computing `MAX+1` without holding the allocator `FOR UPDATE` is
   illegal.
3. If `allocated < 1`, fail `55000` (`taxonomy_ordinal_allocation_invalid`).
4. `UPDATE private.taxonomy_release_ordinal_allocator
   SET next_ordinal = allocated + 1
   WHERE singleton IS TRUE;`
   This is the only private DML the allocator contract permits.
5. Revalidate: no other `public.taxonomy_releases` row (committed or
   this-transaction) already holds `release_ordinal = allocated`.
   Failure `55000` rolls back the increment.
6. `RETURN allocated;`

Concurrent creators: winner is the transaction that first holds the
allocator row. Loser blocks on `FOR UPDATE`, then receives the next
distinct consecutive positive ordinal. Rollback returns the ordinal to
the `GREATEST` computation of the next creator. Ordinal `UPDATE` after
the release insert always fails (column trigger).

### 7.4 `create_taxonomy_release` replacement

013 `CREATE OR REPLACE public.create_taxonomy_release(text,timestamptz,text)`
preserves identity arguments, catalog-executor owner, `service_role`
caller, and `search_path = pg_catalog, public, extensions`. Replacement
body:

1. `allocated := public.allocate_taxonomy_release_ordinal_v02();`
2. insert `DRAFT` with immutable `release_ordinal = allocated`
   (`allocated >= 1`);
3. lock the new release row `FOR UPDATE`;
4. revalidate uniqueness and positivity; failure `55000` rolls back the
   allocator increment with the insert.

The function body contains no `private.` schema qualifier and does not
change `search_path`.

Lexical comparison of `release_code` (`v0.9`, `v0.10`, `v10.0`) is
forbidden in membership tests. Membership is only:

```text
introduced_release_ordinal <= pin_ordinal
AND (retired_release_ordinal IS NULL OR pin_ordinal < retired_release_ordinal)
```

When retired is not null, `introduced_release_ordinal < retired_release_ordinal`
(half-open). Empty/reversed/equal ranges fail verify (`55000`,
`taxonomy_ordinal_range_invalid`).

### 7.5 Concept/alias/relationship create and retire

After ordinal backfill, 013 `CREATE OR REPLACE`s the 012 create/retire
signatures. Create requires the introducing release to be `DRAFT`, locks
release then semantic row, writes `introduced_release_ordinal` from the
release, and forces `retired_release_ordinal` null. Caller-supplied
ordinals are ignored if present and must not differ from the derived
value.

Retire-at-release requires a later `DRAFT` release, locks release then
semantic row, and sets only `retired_release_ordinal`. Effectiveness
begins when that release verifies. 013 `CREATE OR REPLACE
verify_taxonomy_release(text,text)` keeps `DRAFT → VERIFIED` and rejects
empty/reversed ordinal ranges on content that names this release as
retired.

Draft or retired releases cannot start v0.2 evaluations or verify v0.2
rule sets.

### 7.6 Backfill order inside 013

Ordinal columns, allocator table, private allocator function, and
`public.allocate_taxonomy_release_ordinal_v02()` commit **before** any
taxonomy `CREATE OR REPLACE`. `create_taxonomy_release` is replaced only
after the wrapper is installed and EXECUTE-granted to
`foundation_catalog_executor`. Pin tables exist **before**
`start_eligibility_evaluation_v02`.

---

## 8. Recursive truth and `ABSENT`

### 8.1 Four states

| State | Meaning |
|---|---|
| `SATISFIED` | a participant in this projection is met |
| `NOT_SATISFIED` | a participant in this projection is conclusively unmet under closed-world proof |
| `UNKNOWN` | a participant exists and cannot be decided |
| `ABSENT` | zero descendants belong to this projection |

`ABSENT` is not `SATISFIED`, not `UNKNOWN`, not `NOT_SATISFIED`, and not
knowledge-status `NOT_APPLICABLE`. Knowledge-status `NOT_APPLICABLE` maps
to Eligibility `UNKNOWN` on `FULL` (section 12).

### 8.2 Leaf actual (`FULL`) algorithm

Shared by SQL and TypeScript v0.2. Uses pins/snapshots only.

**Program fact.** If the node has no source pins, or **any** pinned
source has `knowledge_status_at_pin <> 'KNOWN'` → actual `UNKNOWN`
(`PROGRAM_FACT_NOT_KNOWN`). v0.2 does not `LIMIT 1` among multiple
sources. Every pinned source must be `KNOWN`; there is no other
aggregation. Every non-`KNOWN` knowledge state including `UNKNOWN`,
`NOT_YET_RESEARCHED`, `NOT_YET_VERIFIED`,
`NOT_PUBLICLY_DISCLOSED`, `NOT_APPLICABLE`, `SOURCE_CONFLICT`, `STALE`
takes this path.

**`HAS_COURSE_CONCEPT`.**

1. Authoritative in-scope `VERIFIED` mapping to `target_concept_id` whose
   course is in the evaluation snapshot, `course_status = 'COMPLETED'`,
   **and** the node has a pinned `VERIFIED` catalog mapping with
   `relation_at_pin = COURSE_EQUIVALENCY` to that concept → `SATISFIED`
   (finalizer writes `eligibility_course_matches`). Without that catalog
   authority the leaf is not `SATISFIED` (section 4.2 item 6).
2. Else if a limiting `PROPOSED` mapping to that concept exists in those
   scopes → `UNKNOWN` (`PROPOSED_MAPPING_LIMITING`).
3. Else if course-absence proof in section 4.2 holds → `NOT_SATISFIED`
   (`REQUIRED_COURSE_ABSENT`) + negative authorization.
4. Else if `UNASSIGNED_CONTEXT` lacks 012 completeness authority
   (section 3.4) → `UNKNOWN`
   (`UNASSIGNED_CONTEXT_COMPLETENESS_UNAVAILABLE`).
5. Else → `UNKNOWN` (`INCOMPLETE_COURSE_OR_MAPPING_COVERAGE` or
   `TAXONOMY_CONCEPT_INACTIVE_AT_PIN` as applicable).

`IN_PROGRESS` / `PLANNED` / `WITHDRAWN` courses never satisfy.
Confidence never satisfies.

**`HAS_TEST`.**

1. In-scope test with `assessment_concept_id = target_concept_id` →
   `SATISFIED` + `eligibility_test_matches`.
2. Else if test-absence proof holds → `NOT_SATISFIED`.
3. Else → `UNKNOWN`.

### 8.3 Projection of a leaf

`private.eligibility_v02_leaf_class`:

- `HARD` + `ORDINARY` → ordinary hard;
- `HARD` + `EXPLICIT_CONDITIONAL` → conditional hard;
- `SOFT` + `ORDINARY` → soft;
- `SOFT` + `EXPLICIT_CONDITIONAL` → verification **fails closed**
  (`55000`, `eligibility_soft_conditional_forbidden`).

| Leaf class | `FULL` | `ORDINARY_BARRIER` | `CONDITIONAL_HARD` | `CONDITIONAL_ONLY` | `SOFT_EXPLANATION` |
|---|---|---|---|---|---|
| ordinary hard | actual | actual | actual | `ABSENT` | `ABSENT` |
| conditional hard | actual | substituted `SATISFIED` | actual | actual | `ABSENT` |
| soft | actual | `ABSENT` | `ABSENT` | `ABSENT` | actual |

### 8.4 Groups, after discarding `ABSENT` children

Let remaining children be the already-projected child values with `ABSENT`
removed. If none remain → `ABSENT`. Do not apply `k`.

**ALL** (any `NOT_SATISFIED` wins, else any `UNKNOWN`, else `SATISFIED`):

| A \ B | `SATISFIED` | `NOT_SATISFIED` | `UNKNOWN` |
|---|---|---|---|
| `SATISFIED` | `SATISFIED` | `NOT_SATISFIED` | `UNKNOWN` |
| `NOT_SATISFIED` | `NOT_SATISFIED` | `NOT_SATISFIED` | `NOT_SATISFIED` |
| `UNKNOWN` | `UNKNOWN` | `NOT_SATISFIED` | `UNKNOWN` |

**ANY** (any `SATISFIED` wins, else any `UNKNOWN`, else `NOT_SATISFIED`):

| A \ B | `SATISFIED` | `NOT_SATISFIED` | `UNKNOWN` |
|---|---|---|---|
| `SATISFIED` | `SATISFIED` | `SATISFIED` | `SATISFIED` |
| `NOT_SATISFIED` | `SATISFIED` | `NOT_SATISFIED` | `UNKNOWN` |
| `UNKNOWN` | `SATISFIED` | `UNKNOWN` | `UNKNOWN` |

n-ary is the same fold.

**`AT_LEAST(projected_minimum_children)`.** `k` is **not**
`minimum_children` after projection and is **not** inferred at
runtime. Read `projected_minimum_children` from
`eligibility_projection_threshold_pins` for
`(group_node_id, projection_kind)`.

Let `n` = remaining count (immediate children that belong to this
projection; section 8.5), `s` = `SATISFIED` count, `u` = `UNKNOWN`
count:

- `n = 0` → `ABSENT`; do not apply `k`; no threshold row is required;
- missing pin row when `n > 0` → finalization **fails closed**
  (`55000`, `eligibility_missing_projected_threshold`);
- `s >= projected_minimum_children` → `SATISFIED`;
- `s + u < projected_minimum_children` → `NOT_SATISFIED`;
- otherwise → `UNKNOWN`.

SQL never infers `k` by subtracting `ABSENT` from `minimum_children`.
SQL never defaults a non-`FULL` `k` from `minimum_children`.

### 8.5 Threshold rows at v0.2 rule verification

Projected descendant membership is recursive from leaf strength/semantics
(section 8.3). A node **belongs** to a projection iff:

- it is a leaf whose projected class is not `ABSENT`; or
- it is a group with at least one descendant (at any depth) that belongs
  to that projection.

`projected_descendant_count` for an `AT_LEAST` group is the number of
**immediate** children that belong to that projection. Nested child
groups that are themselves `ABSENT` in the projection do not count.

A threshold row is required only for `AT_LEAST` groups with
`projected_descendant_count >= 1`. When the count is 0 the group is
`ABSENT` and **no** row is stored.

**`FULL`:** the authoritative threshold is the original rule-tree
`minimum_children`. `verify_program_requirement_rule_set` writes the
normalized `FULL` row when `projected_descendant_count > 0`, with
`projected_minimum_children = minimum_children` and
`projected_descendant_count` equal to the structural child count.
Reviewer insert of `FULL` is rejected
(`22023`, `eligibility_full_threshold_not_reviewer_supplied`).

**`ORDINARY_BARRIER`, `CONDITIONAL_HARD`, `CONDITIONAL_ONLY`,
`SOFT_EXPLANATION`:** explicit reviewer-approved projection semantics.
Inserted on the `DRAFT` rule set by
`insert_requirement_group_projection_threshold`. No default from
`minimum_children`. Retaining every structural child does **not** force
`k = minimum_children`. `1 <= projected_minimum_children <=
projected_descendant_count`.

At verification, for `engine_contract_version = 'eligibility-v0.2'`:

1. compute recursive membership for every node and every projection;
2. require exactly one reviewer threshold for each projected `AT_LEAST`
   group × non-`FULL` projection with count `>= 1`;
3. write the normalized `FULL` row where count `>= 1`;
4. stamp `verification_evidence_id`, `verified_by`, `verified_at` from
   the verify arguments onto every stored row;
5. reject missing, extra, `k < 1`, `k > projected_descendant_count`, a
   row for count `0`, a row whose `rule_set_id` / `group_node_id` is not
   an `AT_LEAST` node of this rule set, or leftover threshold rows for
   `eligibility-v0.1` rule sets.

v0.1 verification in the replaced function **does not** write thresholds
and **rejects** leftover threshold rows for `eligibility-v0.1` rule sets.

Completed evaluations pin the exact
`(rule_set_id, group_node_id, projection_kind,
projected_minimum_children, projected_descendant_count)` identity and
value. Changing the stored `projected_minimum_children` on a fixture
must change SATISFIED / NOT_SATISFIED / UNKNOWN (section 16.D).

### 8.6 Tree integrity at finalize

SQL recomputes every node bottom-up from pins. It rejects missing, extra,
duplicate, disconnected, cyclic, wrong-rule-set, or caller-mismatched
`FULL` results (caller cannot supply them on v0.2). Five projection values
per node are required. `FULL` root cannot be `ABSENT`
(`55000`, `eligibility_full_root_absent`).

---

## 9. Projection model

Requirement strength and semantics remain separate columns. Mixed
descendants under `ALL` / `ANY` / `AT_LEAST` are handled by projecting
each child first, dropping `ABSENT`, then applying the operator with that
projection’s `projected_minimum_children`.

`ORDINARY_BARRIER` preserves tree topology: conditional hard leaves become
`SATISFIED` so they cannot create a barrier; the question is whether an
unavoidable ordinary-hard barrier remains.

`CONDITIONAL_HARD` retains ordinary leaves at actual values so mixed
topology is not lost. This is the frozen “hard-current” projection.

`CONDITIONAL_ONLY` and `SOFT_EXPLANATION` are explanatory. They never
enter the 4×4.

Invalid leaf combination `SOFT` + `EXPLICIT_CONDITIONAL` is rejected at
v0.2 verify, not repaired at evaluate.

---

## 10. Final outcome derivation

Function `private.eligibility_v02_derive_outcome(ordinary, conditional)`
implements this closed table. **The 4×4 table is authoritative.** Rows =
`ORDINARY_BARRIER` root; columns = `CONDITIONAL_HARD` root. Surrounding
prose restates the table and must not invent cells the table does not
contain.

`CONDITIONAL_ONLY` never drives overall outcome. It is not an input to
this function.

Derivation with no implicit cells:

- `ORDINARY_BARRIER = NOT_SATISFIED` → `NOT_ELIGIBLE` regardless of
  conditional;
- `ORDINARY_BARRIER = UNKNOWN` → `UNKNOWN` regardless of conditional;
- `ORDINARY_BARRIER ∈ {SATISFIED, ABSENT}` and
  `CONDITIONAL_HARD ∈ {SATISFIED, ABSENT}` → `ELIGIBLE`;
- `ORDINARY_BARRIER ∈ {SATISFIED, ABSENT}` and
  `CONDITIONAL_HARD = NOT_SATISFIED` → `CONDITIONALLY_ELIGIBLE`;
- `ORDINARY_BARRIER ∈ {SATISFIED, ABSENT}` and
  `CONDITIONAL_HARD = UNKNOWN` → `UNKNOWN`.

`INVALID_STATE` is a finalization failure (`55000`,
`eligibility_projection_invalid_state`), not an outcome:

| `ORDINARY_BARRIER` \ `CONDITIONAL_HARD` | `ABSENT` | `SATISFIED` | `NOT_SATISFIED` | `UNKNOWN` |
|---|---|---|---|---|
| `ABSENT` | `ELIGIBLE` | `ELIGIBLE` | `CONDITIONALLY_ELIGIBLE` | `UNKNOWN` |
| `SATISFIED` | **INVALID_STATE** | `ELIGIBLE` | `CONDITIONALLY_ELIGIBLE` | `UNKNOWN` |
| `NOT_SATISFIED` | **INVALID_STATE** | `NOT_ELIGIBLE` | `NOT_ELIGIBLE` | `NOT_ELIGIBLE` |
| `UNKNOWN` | **INVALID_STATE** | `UNKNOWN` | `UNKNOWN` | `UNKNOWN` |

A non-`ABSENT` ordinary root means at least one ordinary-hard descendant
exists and remains in `CONDITIONAL_HARD`, so conditional `ABSENT` is
impossible. Independent per-projection `projected_minimum_children` can produce
ordinary `NOT_SATISFIED`/`UNKNOWN` with conditional `SATISFIED`; those
cells are real.

Soft projection never causes `NOT_ELIGIBLE`, `UNKNOWN`, or
`CONDITIONALLY_ELIGIBLE`: soft leaves are `ABSENT` in both decision
projections. Soft-only trees are `ABSENT`/`ABSENT` = `ELIGIBLE`. Soft
`UNKNOWN` may appear on `FULL` / `SOFT_EXPLANATION` only.

v0.2 `root_truth_value` is the `FULL` root and does not determine
`outcome`. Explicit conditional means a verified, officially stated,
remediable hard condition. It is never soft and never admission
probability.

`FULL`, `CONDITIONAL_ONLY`, and `SOFT_EXPLANATION` never own outcome.
`CONDITIONAL_ONLY` is explanatory / provenance-only.

---

## 11. Fingerprint schema

### 11.1 Two hashes

| Logical name | Storage | Helper |
|---|---|---|
| `eligibility_v02_input_fingerprint` | `eligibility_evaluations.input_fingerprint` on v0.2 rows | `private.canonical_eligibility_v02_input_fingerprint(uuid)` |
| `eligibility_v02_result_fingerprint` | `eligibility_evaluations.result_fingerprint` | `private.canonical_eligibility_v02_result_fingerprint(uuid)` |

Both are lowercase 64-hex SHA-256 of canonical UTF-8 bytes. Production
persists normalized pin/snapshot/result rows plus these hashes.
**No `bytea`, document `jsonb`, or text payload column stores canonical
bytes.** Golden vectors live only in
`packages/eligibility-engine/contracts/vectors/`.

Seal regenerates the input canonical and stores `input_fingerprint`.
Finalize regenerates the input canonical again, requires equality with the
sealed hash (`55000`, `eligibility_v02_input_fingerprint_drift`),
derives results, regenerates the result canonical, and stores
`result_fingerprint`. Replay regenerates both from pins and fails on
mismatch.

### 11.2 Scalar / container rules (`eligibility-v0.2-c14n1`)

Implemented by `private.canonical_json_v02` and TypeScript
`canonicalizeV02`. Do not hash `jsonb::text`.

- UTF-8, Unicode NFC, RFC 8259 escaping; no BOM; controls as lowercase
  `\u00xx`; invalid Unicode fails;
- boolean = `true` / `false` only;
- SQL NULL vs JSON absence: required keys always present; nullable
  required keys emit JSON `null`;
- UUID = lowercase 8-4-4-4-12;
- timestamp = UTC `YYYY-MM-DDTHH:MM:SS.ffffffZ` (six fractional digits,
  trailing zeros retained); dates = `YYYY-MM-DD`;
- decimal = minimal non-exponent base-10, trailing **fractional** zeros
  removed, `-0` → `0`; integer trailing zeros are significant (`10` stays
  `"10"`, never `"1"`); NaN/infinities fail;
- integer = base-10 without sign padding (`1`, `10`, `100`, `1200` are
  distinct);
- enum = exact uppercase registry label;
- object keys sorted by Unicode scalar value; duplicate/unknown keys fail;
- schema collections are sets: sort by declared key, duplicates illegal;
- opaque `canonicalValue` / student evidence `metadata` keep stored array
  order with duplicates significant and are not re-sorted.

### 11.3 Input logical object

Exact keys and nested shapes from remediation §15.3. Collections and sort
keys are that table. Negative-authorization rows are **excluded**.
Completeness scopes, snapshot membership, mapping pins/status/relation
(the section 5.0 decision universe only),
projection thresholds, catalog evidence/knowledge pins, contract/engine
versions, profile/hash, rule set/version, and taxonomy release/ordinal
**are included**. `REJECTED` and already-`RETIRED` historical mappings
are not pins and are not hashed. An unrelated historical
`REJECTED` / `RETIRED` row therefore does not change the input
fingerprint.

Fingerprint composition follows **this canonical object schema only**.
Generated evaluation-local UUIDs (`scope_id`, `requirement_result_id`,
course/test match IDs) are **not** hashed. Snapshot and negative-authorization
scope identity is `{scopeKind, educationContextId, domain}`. The input
object includes `ruleNodeMappings`. Storage columns that are not named
members of §15.3 / this section
(for example audit timestamps not in the object, executor role, lock
helpers, `private.eligibility_v02_finalize_authorizations`) are not
hashed merely because they exist on a table.

### 11.4 Result logical object

Exact keys from remediation §15.4, including `decisionInputFingerprint`,
five roots (`full` cannot be `ABSENT`), `outcome`, node results, projection
results, matches, and `negativeAuthorizations`. Sort keys are that table.

---

## 12. SQL / TypeScript parity design

### 12.1 Versioned registry

`packages/eligibility-engine/contracts/eligibility-v0.2.json` is data, not
a DSL. Closed sets:

- knowledge states: `KNOWN`, `UNKNOWN`, `NOT_PUBLICLY_DISCLOSED`,
  `NOT_YET_RESEARCHED`, `NOT_YET_VERIFIED`, `NOT_APPLICABLE`,
  `SOURCE_CONFLICT`, `STALE`;
- truth states: `SATISFIED`, `NOT_SATISFIED`, `UNKNOWN`;
- projection values: those plus `ABSENT`;
- outcomes: `ELIGIBLE`, `NOT_ELIGIBLE`, `UNKNOWN`,
  `CONDITIONALLY_ELIGIBLE`;
- projections, operators, strengths, semantics, mapping statuses,
  universe roles, scope kinds, reason codes, missing-data codes,
  contract versions `phase2-v0.2`, `eligibility-v0.2`,
  `eligibility-v0.2-c14n1`.

Generator emits SQL seed/check fragments, TypeScript `as const` unions,
and one JSON Lines corpus. CI `--check` fails on diff. SQL and TypeScript
both execute the corpus and compare canonical-byte hex, both hashes, every
node projection, and outcome. TypeScript exhaustive switches use `never`.
SQL checks registry set equality in both directions.

### 12.2 v0.1 engine unchanged

`packages/eligibility-engine/src/evaluate.ts` and `types.ts` remain the
v0.1 contract (`ruleSchemaVersion: "phase2-v0.1"`,
`engineContractVersion: "eligibility-v0.1"`, three-state
`aggregateTruth`, existing `KnowledgeStatus` union that omits SQL
`UNKNOWN` / `NOT_YET_RESEARCHED`). v0.1 tests stay 8/8. Knowledge-state
parity is **fixed only in v0.2**: every non-`KNOWN` SQL state maps to
Eligibility `UNKNOWN`; `NOT_APPLICABLE` is not a fourth truth value and is
not `ABSENT`.

v0.2 TypeScript lives in `src/v02/evaluate.ts` and accepts
`engineContractVersion: "eligibility-v0.2"` only. It implements sections
8–11. It does not call v0.1 `evaluateEligibility`.

---

## 13. Finalizer lifecycle

`finalize_eligibility_evaluation_v02(p_evaluation_id uuid) returns text`
(the result fingerprint). No outcome argument.

Executable order:

1. Resolve `student_id` from
   `eligibility_evaluations ⋈ student_profile_versions` **without locking**.
2. `private.lock_student_lifecycle(student_id)` (012 helper, unchanged).
3. `private.lock_student_owned_total_order(student_id)` (012 helper,
   unchanged; families 1–3).
4. Lock 013 family-4 snapshot scopes of this evaluation
   `ORDER BY scope_id FOR UPDATE`.
5. Lock remaining 013 children of this evaluation (pins, universe,
   existing 008 manifests/results if any) `ORDER BY` primary UUID.
6. Lock catalog parents after student locks, each `FOR UPDATE` / `FOR KEY
   SHARE` as named, ordered by UUID: pinned `program_requirement_rule_sets`,
   `taxonomy_releases`, referenced `catalog_concept_mappings`. Catalog paths
   do not take the student lock, so this order cannot cycle with them.
7. Revalidate: row exists; `evaluation_state = BUILDING`;
   `inputs_sealed_at` not null; `input_schema_version = 'eligibility-v0.2'`;
   student still present; profile still `FROZEN` with the pinned hash.
8. Re-validate closed-world equalities, mapping universes, taxonomy
   `introduced <= pin < retired` on **pinned** ordinals, projection
   threshold presence.
9. Insert `private.eligibility_v02_finalize_authorizations`.
10. Derive every leaf actual from pins; project five ways; aggregate;
    derive outcome; refuse `INVALID_STATE`; refuse missing
    `projected_minimum_children` pin when `n > 0`.
11. Write `eligibility_requirement_results` (`FULL` three-state),
    projection results, matches, negative authorizations.
12. Regenerate input fingerprint; require equality with sealed hash;
    regenerate result fingerprint.
13. `UPDATE` evaluation to `COMPLETED` with derived `outcome`,
    `root_truth_value` (`FULL` root), fingerprints, `evaluated_at`.
14. Delete the finalize authorization; write student lifecycle audit
    `FINALIZE_V02`.
15. Return `result_fingerprint`.

The function never performs Fit, competitiveness, ranking, probability, or
recommendation. It never reads Fit evaluation state, Fit intents, Fit
completeness, or any Fit domain as eligibility input or outcome. Fit
locks/domain states are not part of the v0.2 Eligibility finalizer.
Calling unchanged 012 `lock_student_owned_total_order` (which serializes
Fit-owned families for student-lock hygiene) does not make Fit state an
eligibility input. It never accepts caller truth or outcome. It never
updates a v0.1 row (`eligibility_v02_api_on_v01_row`).

`start_eligibility_evaluation_v02` uses the same first lock, requires
current heads (section 2.3), inserts `BUILDING` with v0.2 version columns
and copied `taxonomy_release_ordinal`, and audits `START_V02`.

`seal_eligibility_evaluation_inputs_v02` uses the same first lock, proves
section 3–5 equalities, regenerates and stores `input_fingerprint`, sets
`inputs_sealed_at`, and makes snapshot/pin rows immutable.

---

## 14. Privacy extension

`delete_student_data(uuid,text)` is **not** replaced. Owner, callers,
`search_path`, and the 012 student lifecycle lock remain.

013 `CREATE OR REPLACE FUNCTION private.close_student_owned_rows(uuid)`
with the same identity arguments, migration-owner `SECURITY INVOKER`,
executor-only `EXECUTE`, and
`search_path = pg_catalog, public, private, extensions`.

Replacement body **retains the complete 012 anti-join list** (identities,
profiles, completeness, evidence, degrees, courses, tests, experiences,
skills, goals, preferences, student mappings, derived values, lifecycle
audit, `eligibility_evaluations`, Fit evaluations/intents/access
contexts) and **adds** anti-joins for:

- `eligibility_snapshot_scopes` and all membership/universe children;
- every `eligibility_*_pins` table in section 1.4;
- `eligibility_requirement_projection_results`;
- `eligibility_negative_fact_authorizations` and
  `_authorization_scopes`;
- `private.eligibility_v02_finalize_authorizations` (must be empty;
  in-flight finalize must serialize on the student lock and cannot
  commit a leftover authorization after parent delete).

Child FKs `ON DELETE CASCADE` from `eligibility_evaluations` so the 012
`DELETE FROM students` still physically removes v0.2 rows. The helper
proves closure. Privacy deletion remains the intentional end of
replayability and still writes only the 012 non-PII tombstone.

No plugin registry, hook table, or extra public delete function.

---

## 15. Concurrency / lock order

Unchanged 012 identity:
`pg_advisory_xact_lock(hashtextextended('student-lifecycle:' ||
lower(student_id::text), 0))` then `students FOR UPDATE`. Advisory locks
are hints only; correctness is row locks, constraints, and post-lock
revalidation.

**Student-owned v0.2 paths** (start/pin/snapshot/seal/finalize):

1. student lifecycle lock;
2. 012 total order (profiles, fit intents, eligibility then fit
   evaluations);
3. this evaluation’s snapshot scopes by `scope_id`;
4. this evaluation’s remaining children by UUID;
5. catalog parents listed in section 13.

013 does not replace `lock_student_owned_total_order` and does not reorder
families 1–3.

**Taxonomy ordinal create:** `create_taxonomy_release` calls
`public.allocate_taxonomy_release_ordinal_v02()`, which calls
`private.taxonomy_allocate_release_ordinal()`. That helper takes
allocator `FOR UPDATE`, then `GREATEST(next_ordinal, max+1)` while the
lock is held, then advances `next_ordinal`. Catalog executor never
locks the private allocator row itself. Release-row `FOR UPDATE`
follows the insert of the allocated ordinal.

**Winner/loser:** for one `student_id`, winner is the transaction that
first holds `students FOR UPDATE`. Loser revalidates: missing student
`23503`; `COMPLETED` evaluation `55000`; deletion committed → finalize
fails closed. Two-session tests in section 16.J.

---

## 16. Exact test matrix

New SQL file `supabase/tests/005_phase013_eligibility_v02.sql` plus
TypeScript `packages/eligibility-engine/test/v02/`. Negative tests assert
SQLSTATE plus hint/constraint identity on an otherwise valid fixture.
Disabling the intended guard must make the positive attack succeed in a
rollback harness. v0.1 fingerprints and payloads are compared
byte-for-byte in every suite.

### A. Closed-world attacks

| Case | Expected |
|---|---|
| omit a profile course from snapshot/manifest | seal fail `eligibility_course_universe_mismatch` |
| omit a degree | seal fail `eligibility_degree_universe_mismatch` |
| omit a test | seal fail `eligibility_test_universe_mismatch` |
| omit a `VERIFIED` student mapping | seal/finalize fail `eligibility_authoritative_universe_mismatch` |
| extra course or extra unrelated `VERIFIED` mapping | same mismatch fail |
| extra out-of-scope `PROPOSED` mapping | seal/finalize fail |
| omit `UNASSIGNED_CONTEXT` while a null-`student_degree_id` course exists | fail |
| omit empty `UNASSIGNED_CONTEXT` snapshot when no unassigned courses exist | fail (snapshot always required; not a completeness identity) |
| extra NULL-context course in the `UNASSIGNED_CONTEXT` snapshot | seal/finalize fail |
| omit an existing NULL-context course from the `UNASSIGNED_CONTEXT` snapshot | seal/finalize fail `eligibility_course_universe_mismatch` |
| park null-context course on an `EDUCATION_CONTEXT` | fail `eligibility_snapshot_scope_shape` / partition |
| park degree-linked course on `UNASSIGNED_CONTEXT` | fail |
| fabricate a completeness row / pin for `UNASSIGNED_CONTEXT` on a profile that has degrees | fail; 013 does not invent completeness |
| treat optional extra NULL-context `COURSE_*` completeness on a with-degrees profile as `COMPLETE` authority | ignored for negatives; leaf stays `UNKNOWN` |
| wrong education context ID | fail |
| wrong student / wrong profile ID | FK or mismatch fail |
| duplicate scope membership | PK / equality fail |
| `GLOBAL_PROFILE` with non-null context | fail |

### B. Negative authority

| Case | Expected |
|---|---|
| empty complete course universe on a **zero-degree** profile, no proposal, verified catalog equivalency | leaf `NOT_SATISFIED` + authorization scopes include 012-authorized `UNASSIGNED_CONTEXT` |
| same with any `PARTIAL`/`UNKNOWN` course completeness | `UNKNOWN`; no authorization row |
| **B1.1** degree exists + NULL-context satisfying `COMPLETED` course with authoritative pin | leaf `SATISFIED`; match allowed from the pinned unassigned course |
| **B1.2** degree exists + no NULL-context satisfying course + no 012 completeness authority for `UNASSIGNED_CONTEXT` | `UNKNOWN` (`UNASSIGNED_CONTEXT_COMPLETENESS_UNAVAILABLE`); no authorization row |
| **B1.3** omit an existing NULL-context course from the snapshot | seal/finalize failure; not a negative |
| **B1.4** extra NULL-context course in the snapshot | seal/finalize failure |
| `PROPOSED` equivalency to the target concept | `UNKNOWN`; not `NOT_SATISFIED` |
| omit a satisfying `VERIFIED` mapping | finalize fail (not a negative) |
| fabricate authorization without closed proof | insert fail (finalizer-only) |
| `REJECTED`/`RETIRED` at pin time omitted from identity manifest | **does not fail**; outside the decision universe; no pin required |
| `REJECTED`/`RETIRED` pin insert | pin insert fail `eligibility_mapping_status_not_universe_eligible` |
| `REJECTED`/`RETIRED` assigned an AUTHORITATIVE/LIMITING universe row | universe insert/seal fail |
| complete empty `TEST_HISTORY` | test leaf `NOT_SATISFIED` |
| incomplete `TEST_HISTORY` | `UNKNOWN` |
| `HAS_DEGREE` / degree-absence negative | no such predicate; not stored |

### C. Recursive truth

Exhaustive `ALL` / `ANY` / `AT_LEAST` tables over
`{SATISFIED, NOT_SATISFIED, UNKNOWN}` remaining children, plus `ABSENT` at
leaf, nested group, and root positions for each projection. Corpus-driven.
Include `n = 0 → ABSENT` and missing `projected_minimum_children` pin
when `n > 0` → fail closed (`eligibility_missing_projected_threshold`).

### D. Projection tests

- hard + soft children under `ALL`/`ANY`/`AT_LEAST` (mixed hard/soft
  `AT_LEAST`);
- ordinary + explicit conditional (mixed ordinary/conditional `AT_LEAST`);
- nested `AT_LEAST` groups; a group belongs to a projection iff ≥1
  descendant belongs, computed recursively from leaf strength/semantics;
- mixed strength under `AT_LEAST` with distinct
  `projected_minimum_children` ≠ `minimum_children` on the four
  non-`FULL` projections;
- zero projected descendants → `ABSENT`; no threshold row;
- missing projected threshold → rule-set verification rejected and, if
  a `VERIFIED` row is later missing at finalize, finalization rejected;
- **threshold value changes truth:** same remaining children, two
  reviewer `projected_minimum_children` values, SATISFIED vs
  NOT_SATISFIED / UNKNOWN differ; pins must capture the exact value;
- `FULL` threshold equals `minimum_children`; reviewer-supplied `FULL`
  rejected;
- soft-only tree → `ORDINARY_BARRIER`/`CONDITIONAL_HARD` = `ABSENT` →
  `ELIGIBLE`;
- conditional-only tree; `CONDITIONAL_ONLY` root does not change
  `outcome`;
- zero ordinary-hard descendants;
- nested mixed groups five levels deep;
- `SOFT`+`EXPLICIT_CONDITIONAL` rejected at verify;
- `FULL` root `ABSENT` rejected.

### E. Outcome table

All 16 ordinary × conditional root pairs: 13 stored outcomes plus 3
`INVALID_STATE` failures, matching the section 10 **4×4 table** (table
authoritative over prose). Soft-only, conditional-only, ordinary-only,
mixed `ALL`/`ANY`, mixed explicit-threshold alternatives.
`CONDITIONAL_ONLY` never drives outcome.

### F. Taxonomy

- later-introduced concept at pin rejected;
- already-retired-at-pin concept rejected;
- active concept accepted;
- concurrent release creation: distinct consecutive ordinals (TAX-AUTH-5);
- ordinal mutation after insert fails;
- lexical traps `v0.9`, `v0.10`, `v10.0` do not decide membership;
- populated 012 upgrade with later introduced and retired content derives
  both ordinals by exact release-code lookup and preserves the text lifecycle;
- missing release-code reference or empty/reversed derived interval aborts
  the upgrade before constraints become partially installed;
- empty/reversed introduced/retired ranges fail verify;
- 012 taxonomy lifecycle tests still pass without ordinal assertions.

### G. Replay

After v0.2 `COMPLETED`:

- retire the live mapping, change live taxonomy retirement ordinal, move
  canonical head, add a source revision;
- regenerate fingerprints from pins; hashes unchanged;
- new `start_eligibility_evaluation_v02` using the retired mapping fails;
- v0.1 completed rows remain byte-identical.

Temporal-boundary cases:

- start while a mapping is `VERIFIED`, retire it before its pin insert →
  pin insert fails; start did not freeze an unpinned live row;
- pin a `VERIFIED` mapping, retire it afterward but before seal/finalize →
  seal/finalize and replay succeed from `status_at_pin = VERIFIED`;
- mapping already `REJECTED` or `RETIRED` at the pin boundary → no pin
  is created; omission does not fail seal/finalize (tests M2, M3);
- attempt to pin a mapping that is already `PROPOSED`, `REJECTED`, or
  `RETIRED` as `VERIFIED` → pin payload mismatch/fail; caller cannot
  fabricate at-use authority (test M7).

### H. Fingerprint

- insertion-order permutation of pins → same input hash;
- replace one course or mapping ID → different hash even if concept
  matches;
- `status_at_pin` / `relation_at_pin` change → different hash;
- unrelated historical `REJECTED` / already-`RETIRED` mapping → same
  input hash (outside the decision universe; test M8);
- golden vectors for UUID, JSON `null`, booleans, decimals (`-0`, trailing
  zeros), timestamps with six fractional digits;
- duplicate collection members rejected before hashing;
- result fingerprint deterministic; negative-auth included in result only;
- production `\d` / information_schema proves no canonical-byte column;
- v0.1 `input_fingerprint` values unchanged.

### I. SQL / TypeScript parity

Same corpus through `private.eligibility_v02_*` SQL helpers (exposed to
tests via `service_role` only on a test wrapper, or executed inside 005)
and `src/v02/evaluate.ts`. Assert canonical hex, both hashes, five roots,
outcome. Generator `--check`. Eight knowledge states each round-trip to
`UNKNOWN` except `KNOWN`. v0.1 `npm test` remains 8/8.

### J. Concurrency (two-session)

Each asserts block/unblock plus terminal SQLSTATE/hint:

- v0.2 start vs catalog mapping retirement / rule-set retirement;
- `finalize_eligibility_evaluation_v02` vs `delete_student_data` on the
  same `students` row lock;
- snapshot insert vs privacy deletion;
- concurrent `create_taxonomy_release` ordinal allocation (TAX-AUTH-5);
- seal vs finalize on one evaluation (one sealed tree only);
- advisory collision extra-blocks only; disabling advisory still preserves
  invariants through row locks.

### K. 008 match-insert compatibility (`validate_eligibility_match_insert`)

- **K.1** v0.1 still rejects a currently `RETIRED` live mapping exactly
  as 008 did (live `mapping_status` on
  `eligibility_course_matches_validate` /
  `eligibility_test_matches_validate`);
- **K.2** v0.2 starts while the mapping is `VERIFIED`, pins it, mapping
  is later `RETIRED`; v0.2 finalization and replay still succeed from
  `status_at_pin`;
- **K.3** v0.2 cannot fabricate a `VERIFIED` pin from a mapping that was
  not `VERIFIED` at the locked pin boundary (`eligibility_pin_payload_mismatch`);
- **K.4** wrong mapping pin, `relation_at_pin`, or concept fails match
  insert / finalize;
- **K.5** historical v0.1 evaluations remain byte-identical (payloads,
  `input_fingerprint`, matches).

### M. Mapping-universe pin law (section 5.0)

| Case | Expected |
|---|---|
| **M1.** Mapping is `VERIFIED` at start and is pinned. Later live `RETIRED`. | v0.2 finalization and replay still succeed from `status_at_pin = VERIFIED`. Match insert remains valid. |
| **M2.** Mapping is `RETIRED` before start. | Excluded from the required mapping universe; no pin is created. Seal/finalize do not fail for its omission. |
| **M3.** Mapping is `REJECTED` before start. | Excluded from the required mapping universe; no pin is created. Seal/finalize do not fail for its omission. It MUST NOT satisfy and MUST NOT independently create `UNKNOWN`. |
| **M4.** In-scope `VERIFIED` mapping is omitted. | Finalization fails (`eligibility_authoritative_universe_mismatch`). |
| **M5.** Relevant `PROPOSED` mapping is omitted where it should act as limiting evidence. | Finalization fails, or the exact contract-defined `UNKNOWN` proof cannot be formed. |
| **M6.** `PROPOSED` mapping is pinned. | It cannot satisfy a requirement. A leaf that would otherwise go negative becomes `UNKNOWN` (`PROPOSED_MAPPING_LIMITING`) when the contract so requires. |
| **M7.** Caller fabricates `status_at_pin = VERIFIED` for a mapping that was `PROPOSED`, `REJECTED`, or `RETIRED` at the pin boundary. | Reject (`eligibility_pin_payload_mismatch` or `eligibility_mapping_status_not_universe_eligible`). |
| **M8.** An unrelated historical `REJECTED` / `RETIRED` mapping exists on the frozen profile. | It does not change the input fingerprint; it is outside the decision universe and is not hashed. |

### N. Taxonomy ordinal authorization bridge (TAX-AUTH)

These eight cases are mandatory 013 tests. They prove section 0
decision 12 and section 7. Disabling the intended grant/USAGE/DEFINER
guard must make the positive attack succeed in a rollback harness.

| Case | Expected |
|---|---|
| **TAX-AUTH-1.** After 013, `foundation_catalog_executor` `USAGE` on `private`. | `has_schema_privilege('foundation_catalog_executor', 'private', 'USAGE')` is false. 012 D-USAGE semantics unchanged. |
| **TAX-AUTH-2.** Catalog-executor creation of a taxonomy release. | Succeeds only through `public.create_taxonomy_release(text,timestamptz,text)`. The wrapper does not insert a `taxonomy_releases` row. Runtime direct `INSERT` into `taxonomy_releases` fails. The persisted `release_ordinal` equals the value allocated in that transaction. |
| **TAX-AUTH-3.** Direct invocation of `public.allocate_taxonomy_release_ordinal_v02()` by `service_role`, `authenticated`, `anon`, or `PUBLIC`. | Rejected (`42501`). Those roles have no EXECUTE. |
| **TAX-AUTH-4.** Direct read/write of `private.taxonomy_release_ordinal_allocator` by `foundation_catalog_executor`. | Rejected (no schema `USAGE` and no table DML). Direct `EXECUTE` of `private.taxonomy_allocate_release_ordinal()` by catalog executor is also rejected. |
| **TAX-AUTH-5.** Two concurrent `create_taxonomy_release` calls. | Distinct consecutive positive ordinals. Winner holds allocator `FOR UPDATE` first; loser blocks, then allocates the next ordinal. Not an unlocked `max+1` race. |
| **TAX-AUTH-6.** Caller-supplied or post-insert ordinal manipulation. | Wrapper and private allocator take no ordinal argument. `create_taxonomy_release` identity arguments remain `(text,timestamptz,text)` with no ordinal parameter. `UPDATE` of `release_ordinal` after insert fails (column trigger). |
| **TAX-AUTH-7.** Wrapper `search_path`. | `proconfig` is exactly `pg_catalog, private`. It contains no `pg_temp` and no attacker-writable schema. Catalog-executor `create_taxonomy_release` `search_path` remains `pg_catalog, public, extensions` (no `private`). |
| **TAX-AUTH-8.** Wrapper/private-allocator private DML surface. | Wrapper `pg_get_functiondef` calls only `private.taxonomy_allocate_release_ordinal()` and names no private table. Private allocator `pg_get_functiondef` names no private relation other than `private.taxonomy_release_ordinal_allocator` and calls no other private mutator. A successful allocate-via-create leaves other private table row counts unchanged. The allocator may only `UPDATE next_ordinal` on the singleton row. |

### Regression gates 013 must keep green

Clean 001–013 rebuild; populated 012→013 upgrade; tests
`001_education_foundation.sql`, `002_phase2_eligibility.sql`,
`003_phase3_fit.sql`, `004_phase012_foundation_hardening.sql`;
TAX-AUTH-1 through TAX-AUTH-8; no 014 objects; no Fit Engine package.

---

## 17. Migration upgrade strategy

1. **File:** `supabase/migrations/202608200013_eligibility_correctness_v02.sql`
   only. Do not edit `001`–`012`.
2. **Preflight:** assert executor roles exist with 012 attributes; abort
   if 9B objects already exist.
3. **Taxonomy ordinals first:** add columns, backfill `v0.1` = 1 and other
   releases by `created_at, release_code`, create allocator table, install
   `private.taxonomy_allocate_release_ordinal()` and
   `public.allocate_taxonomy_release_ordinal_v02()` with section 7.2
   choreography (migration-owner DEFINER; no catalog-executor `USAGE`
   on `private`; EXECUTE on the wrapper only to catalog executor), then
   `CREATE OR REPLACE` taxonomy functions. `create_taxonomy_release`
   calls the public wrapper and does not name `private`.
4. **Rule-set contract check** replacement; threshold table.
5. **Evaluation discriminator columns and CHECKs.**
6. **Pin / snapshot / projection / negative / authorization tables**,
   RLS owner-read matching 008
   (`current_user_owns_profile(e.profile_version_id)`), assembly guards,
   revoke runtime DML.
7. **9B functions** with §3.1 ownership transfer; coexistence
   discriminators on v0.1 seal/finalize/result-insert;
   `CREATE OR REPLACE public.validate_eligibility_match_insert()`
   (section 5.4; trigger names unchanged).
8. **`CREATE OR REPLACE private.close_student_owned_rows`.**
9. **Registry:** insert/update `foundation_function_contracts` for 9B and
   replaced signatures; bidirectional equality with section 1.5.
10. **TypeScript** v0.2 module + generator; do not change v0.1 semantics.
11. **Docs:** this plan is authoritative for 013; README /
    `PRODUCT_ARCHITECTURE` point here. Do not edit
    `PHASE_1_2_FOUNDATION_HARDENING_FREEZE.md` guarantees.
12. **014** remains unscheduled Financial-only work after 013 acceptance.
    Fit Engine remains unauthorized.

Upgrade of a populated 012 database: only additive DDL, backfill of
ordinals, and function replacement. Existing evaluations, fingerprints,
taxonomy `v0.1` release code, and 012 lock/grant rows stay.

Acceptance is remediation §18 013 list (rebuild, upgrade, 012 gates
green, closed-world, pins, `ABSENT`, thresholds, 4×4, ordinals, both
fingerprints, parity corpus, derived-outcome finalizer, privacy
extension, TAX-AUTH-1 through TAX-AUTH-8, no 012 primitive redesign,
catalog-executor `USAGE` on `private` remains false). Contract review names
`foundation-integrity-v1`, `phase2-v0.2`, `eligibility-v0.2`,
`eligibility-v0.2-c14n1`.

---

## 18. Unresolved blockers

None remaining. B1 (`UNASSIGNED_CONTEXT` completeness), B2 (projected
`AT_LEAST` thresholds), and B3 (008 live match validator) are closed in
sections 0.6–0.8, 3.4, 4.2, 5.4, and 8.5 without changing frozen 012
semantics. The implementation audit additionally closes the all-children
projection-threshold fallback, the start-versus-pin temporal boundary,
and populated-012 taxonomy ordinal backfill. The remaining approval
blocker — `REJECTED` / `RETIRED` mapping pin identity — is closed by
section 0 decision 11 and section 5.0: the decision mapping universe is
in-scope `VERIFIED` plus contract-relevant in-scope `PROPOSED`;
`REJECTED` and already-`RETIRED` are excluded from both sides and are
never pinned. The taxonomy ordinal authorization defect —
`create_taxonomy_release` owned by `foundation_catalog_executor` versus
the private allocator — is closed by section 0 decision 12 and section
7: 013 installs `public.allocate_taxonomy_release_ordinal_v02()` as a
migration-owner SECURITY DEFINER bridge; catalog-executor `USAGE` on
`private` remains false; 012 D-USAGE is not amended. Clarifications (4×4
authority, `CONDITIONAL_ONLY`, no `HAS_DEGREE`, fingerprint schema
membership, Fit excluded from the v0.2 finalizer, completeness-pin
`scope_id` nullable, locked pin-boundary meaning of “`VERIFIED` at
start”) are recorded in sections 0, 2.3, 3.3, 5, 10, 11, and 13.

`freeze_student_profile_version()` is not replaced. Migrations `001`–`012`
are not edited. Migration 013 is not created by this revision. 014 and
Fit Engine remain unauthorized.

MIGRATION 013 TAXONOMY AUTHORIZATION DEFECT CLOSED — READY TO RESUME IMPLEMENTATION
