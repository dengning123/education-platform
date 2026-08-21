# Phase 1/2 Frozen Foundation Remediation Plan

Status: **012 FROZEN — Foundation Hardening / Gate 1**  
Date: **2026-08-20**  
Scope: **additive migrations 012 and 013; 014 is dependency notation only**  
Baseline inspected: **migrations 001–011, SQL tests 001–003, Phase 1–3
freeze/specification documents, and the Eligibility package contract**  
Freeze record: **[`PHASE_1_2_FOUNDATION_HARDENING_FREEZE.md`](PHASE_1_2_FOUNDATION_HARDENING_FREEZE.md)**  
Next authorized phase: **Migration 013 — Eligibility Correctness v0.2**

## 1. Purpose, boundary, and fixed sequence

This plan closes the frozen-foundation defects without editing, squashing, or
reinterpreting migrations `001`–`011`. It authorizes no migration, SQL test,
TypeScript, Fit Engine, or Financial implementation.

The only implementation sequence is:

1. `202608200012_frozen_foundation_critical_hardening.sql`;
2. `202608200013_eligibility_semantic_replay_hardening.sql`;
3. a separately approved `014`, after 012 and 013, for the already identified
   Fit Financial `billing_basis` defect.

No capability system, policy DSL, provenance graph, or new service boundary is
introduced.

### 1.1 Frozen migration ownership rule

**012 may:**

- harden objects that already exist in migrations 001–011;
- add new foundation-level ledgers/primitives required to safely govern those
  existing objects;
- add authorization, concurrency, provenance, applicability, lifecycle,
  privacy, and historical-integrity infrastructure reusable by later phases.

**012 must NOT create Eligibility v0.2 semantic structures.**

**013 exclusively owns:**

- Eligibility v0.2 closed-world domain snapshots;
- negative-authority/universe tables;
- replay pin tables specific to Eligibility v0.2;
- projection/`ABSENT` semantics;
- projected `AT_LEAST` thresholds;
- taxonomy release ordinal infrastructure (ordinals are required only for
  v0.2 release-validity semantics; no independent 001–011 invariant requires
  them — see section 15.1);
- Eligibility v0.2 decision/result fingerprint structures;
- the v0.2 outcome-deriving finalizer.

**014 remains Phase 3 Financial-only.**

### 1.2 Exact 012 scope

`202608200012_frozen_foundation_critical_hardening.sql` owns only A–I:

**A. Authorization / privilege hardening.** Executor roles and installation
choreography; `PUBLIC`/runtime `EXECUTE` restrictions; direct lifecycle DML
revocation; GUC authorization neutralization across objects already existing
in 001–011; trusted `search_path`/function-shadowing hardening.

**B. Shared locking primitives.** Student lifecycle lock; source
identity/revision locking; catalog/rule/mapping lifecycle locking for existing
objects; canonical-selection concurrency; primary-school concurrency; privacy
deletion serialization.

**C. Evidence applicability foundation.** Normalized applicability ledger;
exact applicability head identity; verified/current-head lifecycle;
`LEGACY_UNASSERTED` treatment; canonical selection hardened to require valid
applicability authority for new selections/reselections.

**D. Provenance/source revision foundation.** Source identity; immutable
revisions; one current head; exact historical evidence-to-revision linkage;
controlled revision lifecycle.

**E. Existing-object lifecycle hardening** for objects already present in
001–011: catalog mappings; student mappings; existing rule sets; existing
taxonomy releases only to the extent needed to prevent unsafe direct
lifecycle mutation; canonical observations/selections; existing Eligibility
v0.1 evaluations/manifests/results; Fit definitions/context/evaluations from
009–011; profile/intent freeze; privacy deletion.

**F. Existing historical/replay integrity.** Semantic immutability of existing
verified/retired objects; status-at-use immutability where it can be enforced
without creating Eligibility v0.2 pin infrastructure; no silent rewriting of
completed v0.1/Phase 3 history.

**G. Primary-school invariant.**

**H. `program_derived_features` treatment as already approved in section 11.**

**I. Test repairs and 012 adversarial/concurrency tests.**

**012 must NOT create:**

- Eligibility v0.2 domain snapshots;
- Eligibility v0.2 negative-authority rows;
- Eligibility v0.2 projection tables;
- projection thresholds;
- Eligibility v0.2 replay pin tables;
- Eligibility v0.2 fingerprint schema;
- v0.2 taxonomy ordinal structures (they exist solely for 013 semantics).

### 1.3 Eligibility finalizer boundary

Migration 008 owns `finalize_eligibility_evaluation(uuid, eligibility_outcome)`
as the Eligibility v0.1 historical API. 012 may harden its authorization path,
direct-DML protection, concurrency, immutability, and security properties.
012 must NOT change its semantic contract, drop the caller `outcome` argument,
derive v0.2 projections, or replace it with a derived-outcome v0.2 finalizer.

013 introduces the versioned v0.2 API
`finalize_eligibility_evaluation_v02(uuid)`. It must not silently overload or
replace the frozen v0.1 signature. Historical v0.1 evaluations remain
replayable under the v0.1 contract. The v0.2 finalizer derives persisted tree
projections and overall outcome, never trusts caller outcome, and operates
only on v0.2 evaluations.

### 1.4 Compatibility rule

013 may build on 012 primitives but may not require semantic redesign of:

- executor-role model;
- direct-DML policy;
- trusted `search_path` policy;
- student lifecycle lock identity/order;
- source revision model;
- evidence applicability model;
- source/current-head locking model.

If 013 needs a new semantic capability, it must be additive on top of those
frozen primitives. 013 installs section 9B entry points with the section 3.1
choreography and may `CREATE OR REPLACE` only the named 012 helpers/entry
points listed in sections 9B, 14, and 15.1, preserving public signatures and
the 012 security/lock contract.

## 2. Compatibility and historical-row law

1. Existing primary keys, source/evidence rows, observations, selections,
   mappings, profiles, rules, manifests, evaluations, results, hashes, and
   fingerprints remain byte-for-byte unchanged.
2. A pre-012 guarantee that cannot be proved is represented as
   `LEGACY_UNASSERTED`; it is never inferred from historical selection or use.
3. Completed Eligibility v0.1 and Fit v0.1 evaluations remain readable with
   their original semantics. Neither is re-finalized.
4. Existing verified definitions and rule sets retain identity. A new
   evaluation may reuse one only if every new prospective gate passes; failure
   requires a new version, not mutation.
5. “Valid now” and “valid for replay” are separate. A completed evaluation
   reads immutable pins; a new evaluation must additionally pass current-start
   validation.
6. Privacy deletion is the sole intentional end of student-owned replay and
   leaves only the non-linkable tombstone defined in section 14. 012 closes
   over 001–011 student-owned rows plus new 012 student-owned foundation
   rows. 013 extends that closure additively; it does not redesign the 012
   outer function, lock, or security contract.
7. 012 may backfill additive metadata and normalized ledgers, but may not
   rewrite an old business row to manufacture compliance.

## 3. Exact execution and guard model

012 creates three migration-owned `NOLOGIN`, `NOBYPASSRLS`, `NOCREATEROLE`,
`NOCREATEDB`, `NOSUPERUSER`, `NOINHERIT` roles:

- `foundation_catalog_executor`;
- `foundation_student_executor`;
- `foundation_evaluation_executor`.

They own no tables or schemas and receive no membership in one another.
`service_role`, `authenticated`, `anon`, and `PUBLIC` receive no membership and
no `SET ROLE` path to them. The migration/deployment owner retains ownership of
tables, trigger functions, and validator helpers.

The controlled entry points listed below are `SECURITY DEFINER`, owned by the
corresponding executor, and have a fixed `SET search_path`:

- catalog/taxonomy/registry entry points:
  `pg_catalog, public, extensions`;
- student/privacy entry points:
  `pg_catalog, public, private, extensions`;
- Eligibility/Fit assembly and finalization entry points:
  `pg_catalog, public, private, extensions`.

No entry point includes `pg_temp`; every object reference is schema-qualified.
The executor owns only its entry-point functions. Each entry point calls
validator/serializer helpers that are `SECURITY INVOKER` (the PostgreSQL
default), owned by the migration owner, and fully schema-qualified.

Every schema on an entry-point path is trusted by privilege, not by name. 012
revokes `CREATE` on `public`, `private`, `extensions`, and every other
non-system path schema from `PUBLIC`, `anon`, `authenticated`, `service_role`,
`foundation_catalog_executor`, `foundation_student_executor`, and
`foundation_evaluation_executor`. The same `REVOKE CREATE` is issued for
`pg_catalog`; hosted Supabase does not require rewriting `pg_catalog` ACLs
because untrusted `CREATE` there is already impossible, and 012 does not take
ownership of `pg_catalog`. None of those roles may create or replace
functions, operators, casts, types, or relations in a path schema. Only the
migration owner may create or replace application objects in `public` and
`private`; no application object is created in `pg_catalog`. Extension
installation and placement in `extensions` are deployment-controlled by the
database deployment owner; runtime and executor roles cannot install, update,
relocate, or shadow extensions. Executor roles own only the exact approved
entry-point functions and still have no schema `CREATE`. All function calls
and object references are schema-qualified, including `pg_catalog` and
`extensions` calls.

The only exception is the transaction-local executor `CREATE` grant required
for the ownership transfers in section 3.1. It is granted after runtime
revocations, used only by the migration owner for exact-signature transfer,
revoked before installation assertions, and never exists in an accepted
database state.

Installation assertions evaluate
`has_schema_privilege(role_name, schema_name, 'CREATE')` for every
role/schema pair above and require false, except for the migration/deployment
owner cases just stated. Adversarial installation tests attempt same-name
function, operator, and relation shadows in each path schema as
`authenticated`, `service_role`, and every executor and require privilege
denial before invoking each entry point.

All trigger guards are `SECURITY INVOKER`/default and owned by the migration
owner. A controlled transition is accepted only when `current_user` equals the
one exact executor named for that table family. Ordinary draft-content guards
validate shape and parent state but do not grant transition authority.
`session_user`, JWT claims, GUCs, and RLS never authorize lifecycle DML.

### 3.1 Executable migration ownership choreography

012 is run by the deployment migration role, called `foundation_migration_owner`
in this contract. That role is the database owner of `public` and `private`.
Installation preflight fails before any executor DDL unless all of the
following are true of `current_user`: `rolcreaterole`; ownership of `public`
and `private`; ability to `GRANT <executor> TO current_user WITH ADMIN OPTION`;
and ability to grant table DML and schema `USAGE`/`CREATE`. Superuser is not
required and is not assumed.

**Hosted Supabase feasibility.** The migration runner is the project `postgres`
role (CLI/`supabase db push`/dashboard migrations), never `service_role`,
`authenticated`, `anon`, or `authenticator`. Hosted `postgres` has
`CREATEROLE` and can create the three `NOLOGIN` executors, grant them to
itself `WITH ADMIN OPTION`, `SET ROLE`/`SET LOCAL ROLE` those NOLOGIN roles,
`ALTER FUNCTION ... OWNER TO` them, and grant/revoke schema `CREATE`/`USAGE`.
012 does not take ownership of `extensions`, `auth`, `storage`, or
`pg_catalog`. If a hosted project denies `CREATE ROLE`, `GRANT ... WITH ADMIN
OPTION`, temporary schema `CREATE`, or `ALTER FUNCTION OWNER`, preflight fails
closed. There is no fallback that leaves a `SECURITY DEFINER` function owned
by `postgres`, `service_role`, or `PUBLIC`.

Each executor is created with exactly these attributes and no others:

`NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS
NOREPLICATION`. No `IN ROLE` membership. No `SET ROLE` grant to any runtime
role.

For each executor, installation uses this exact transactional order. Steps 4–8
run once per entry-point signature from **section 9A** during 012, and once
per **section 9B** signature during 013. 012 must not install 9B objects.
013 must not redesign 9A signatures, owners, callers, search_path, or lock
identity.

1. `CREATE ROLE <executor> NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB
   NOCREATEROLE NOBYPASSRLS NOREPLICATION` if absent; if present, assert every
   attribute above and that `foundation_migration_owner` is its administrator.
2. `GRANT <executor> TO foundation_migration_owner WITH ADMIN OPTION` so this
   and later migrations can `SET ROLE` for exact-owner maintenance. No other
   grantee.
3. Permanent (post-install retained) `GRANT USAGE ON SCHEMA` for the executor’s
   required schemas: all three executors receive `USAGE` on `public` and
   `extensions`; student and evaluation executors also receive `USAGE` on
   `private`; catalog executor does not receive `private` USAGE. Plus the
   exact table/sequence DML listed in section 4. USAGE is not a CREATE grant.
4. Temporary migration-only `GRANT CREATE ON SCHEMA <function schema> TO
   <executor>`. PostgreSQL requires the new owner to have schema `CREATE`
   before `ALTER FUNCTION ... OWNER TO` succeeds. This grant must not exist
   after step 8.
5. As `foundation_migration_owner`, `CREATE OR REPLACE FUNCTION` the exact
   signature, `ALTER FUNCTION ... SET search_path = <fixed path>`, then
   **immediately** `REVOKE ALL ON FUNCTION <schema>.<name>(<identity
   arguments>) FROM PUBLIC, anon, authenticated, service_role,
   authenticator`. Identity arguments are `pg_get_function_identity_arguments`.
   PostgreSQL grants `EXECUTE` to `PUBLIC` at `CREATE FUNCTION` time; that
   grant must not survive this step.
6. `ALTER FUNCTION <schema>.<name>(<identity arguments>) OWNER TO <executor>`.
7. Immediately after ownership transfer, **again** `REVOKE ALL ON FUNCTION
   <exact identity signature> FROM PUBLIC, anon, authenticated, service_role,
   authenticator` (defense in depth against default privileges), then
   `GRANT EXECUTE ON FUNCTION <exact identity signature>` only to the caller
   roles listed for that row in section 9A (012) or 9B (013). Helpers used by
   the entry point receive `GRANT EXECUTE` only to the owning executor, never
   to `service_role`, `authenticated`, `anon`, or `PUBLIC`.
8. After the executor’s final ownership transfer in this migration,
   `REVOKE CREATE ON SCHEMA <each granted schema> FROM <executor>`. Retain
   schema `USAGE` and required table DML only. `has_schema_privilege(executor,
   schema, 'CREATE')` must then be false for every path schema.
9. Create executor-specific RLS policies (`USING`/`WITH CHECK` require exact
   `current_user`) and `REVOKE INSERT, UPDATE, DELETE` on every lifecycle table
   from `PUBLIC, anon, authenticated, service_role`.
10. Run the verification queries below in the same transaction. Any non-empty
    failure relation aborts 012 with no commit.

Future migrations replace an executor-owned entry point only in one
transaction: migration owner temporarily grants that executor schema `CREATE`,
executes `SET LOCAL ROLE <executor>`, replaces the exact signature and resets
its path, executes `RESET ROLE`, immediately revokes `PUBLIC`/`anon`/
`authenticated`/`service_role` `EXECUTE`, re-grants section 9A/9B callers,
revokes schema `CREATE`, and reruns every post-install assertion before
commit. The migration owner’s administered membership is the
ownership-maintenance mechanism. Runtime roles have no executor membership
and therefore cannot `SET ROLE` an executor.

`foundation_function_contracts` records exact schema, name, identity
arguments, owner role, `prosecdef`, `proconfig` search_path, allowed caller
roles, and body digest (`sha256(pg_get_functiondef(...))`).

**Post-install verification queries** (all must return zero violating rows
before commit):

```sql
-- A. Executor attributes and NOLOGIN.
SELECT r.rolname
FROM pg_roles r
WHERE r.rolname IN (
        'foundation_catalog_executor',
        'foundation_student_executor',
        'foundation_evaluation_executor'
      )
  AND (
        r.rolcanlogin OR r.rolbypassrls OR r.rolcreaterole
        OR r.rolcreatedb OR r.rolsuper OR r.rolinherit
        OR r.rolreplication
      );

-- B. Executors own only intended entry points; no tables/schemas.
SELECT n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
JOIN pg_roles r ON r.oid = p.proowner
WHERE r.rolname IN (
        'foundation_catalog_executor',
        'foundation_student_executor',
        'foundation_evaluation_executor'
      )
  AND NOT EXISTS (
        SELECT 1 FROM public.foundation_function_contracts c
        WHERE c.schema_name = n.nspname
          AND c.function_name = p.proname
          AND c.identity_arguments = pg_get_function_identity_arguments(p.oid)
          AND c.owner_role = r.rolname
      )
UNION ALL
SELECT n.nspname, t.relname, 'RELATION_OWNED_BY_EXECUTOR'
FROM pg_class t
JOIN pg_namespace n ON n.oid = t.relnamespace
JOIN pg_roles r ON r.oid = t.relowner
WHERE r.rolname IN (
        'foundation_catalog_executor',
        'foundation_student_executor',
        'foundation_evaluation_executor'
      );

-- C. No named runtime/executor CREATE on any SECURITY DEFINER path schema.
SELECT role_name, schema_name
FROM (
  SELECT unnest(ARRAY[
           'anon','authenticated','service_role','authenticator',
           'foundation_catalog_executor','foundation_student_executor',
           'foundation_evaluation_executor'
         ]) AS role_name
) roles
CROSS JOIN (
  SELECT unnest(ARRAY['pg_catalog','public','private','extensions']) AS schema_name
) schemas
WHERE has_schema_privilege(roles.role_name, schemas.schema_name, 'CREATE');

-- C-PUBLIC. PUBLIC is not a pg_roles row. 012 writes explicit nspacl on
-- public, private, and extensions (never on pg_catalog). Hosted pg_catalog
-- ACLs are not rewritten; untrusted CREATE there is already impossible.
SELECT n.nspname
FROM pg_namespace n
WHERE n.nspname IN ('public','private','extensions')
  AND n.nspacl IS NULL
UNION ALL
SELECT n.nspname
FROM pg_namespace n
CROSS JOIN LATERAL aclexplode(n.nspacl) a
WHERE n.nspname IN ('public','private','extensions')
  AND n.nspacl IS NOT NULL
  AND a.grantee = 0
  AND a.privilege_type = 'CREATE';

-- D. Executors have no schema CREATE (same as C for those three roles).
-- D-USAGE. Required USAGE must be present after revoke of CREATE:
--   catalog executor: public and extensions USAGE true; private USAGE false;
--   student and evaluation executors: public, private, and extensions USAGE true.
SELECT 'missing_usage' AS kind, r.rolname, n.nspname
FROM pg_roles r
CROSS JOIN pg_namespace n
WHERE (
        (r.rolname = 'foundation_catalog_executor'
         AND n.nspname IN ('public','extensions'))
        OR
        (r.rolname IN (
               'foundation_student_executor',
               'foundation_evaluation_executor'
             )
         AND n.nspname IN ('public','private','extensions'))
      )
  AND NOT has_schema_privilege(r.rolname, n.nspname, 'USAGE');

-- E. PUBLIC/anon have no EXECUTE on controlled or internal functions.
SELECT routine_schema, routine_name
FROM information_schema.routine_privileges
WHERE grantee IN ('PUBLIC','anon')
  AND privilege_type = 'EXECUTE'
  AND routine_schema IN ('public','private');

-- F. authenticated executes only the two owner-read helpers.
SELECT routine_schema, routine_name
FROM information_schema.routine_privileges
WHERE grantee = 'authenticated'
  AND privilege_type = 'EXECUTE'
  AND routine_schema IN ('public','private')
  AND NOT (
        routine_schema = 'public'
        AND routine_name IN (
              'current_user_owns_student',
              'current_user_owns_profile'
            )
      );

-- G. service_role has no direct INSERT/UPDATE/DELETE on lifecycle tables
--    named in section 4, and no EXECUTE on helpers/guards/serializers.
SELECT table_schema, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE grantee = 'service_role'
  AND privilege_type IN ('INSERT','UPDATE','DELETE')
  AND table_schema IN ('public','private');

-- H. No runtime role is a member of an executor.
SELECT r.rolname AS member, e.rolname AS executor
FROM pg_auth_members m
JOIN pg_roles r ON r.oid = m.member
JOIN pg_roles e ON e.oid = m.roleid
WHERE e.rolname IN (
        'foundation_catalog_executor',
        'foundation_student_executor',
        'foundation_evaluation_executor'
      )
  AND r.rolname IN (
        'anon','authenticated','service_role','authenticator','PUBLIC'
      );

-- I. Contract digest, owner, prosecdef, and search_path match section 9A
--    after 012, and sections 9A+9B after 013.
--    Implemented as a join of foundation_function_contracts to pg_proc;
--    any extra/missing overload, wrong owner, missing SET search_path,
--    or body-digest drift is a violating row.
--    After 012 this query must not require 9B names.
```

Adversarial installation tests, still inside the 012 transaction, attempt
`CREATE FUNCTION`/`CREATE OPERATOR`/`CREATE TABLE` of the same name as each
9A entry point in each path schema as `authenticated`, `service_role`, and
every executor, and require privilege denial (`42501`) before invoking each
entry point. Any mismatch aborts 012. 013 repeats the same attacks for 9B
signatures. The 012 entry-point inventory is section 9A only.

**Accepted post-install state (closed):** NOLOGIN executors own only intended
entry points; executors have schema `USAGE` where required and **no** schema
`CREATE`; `authenticated` cannot execute helpers; `service_role` has no direct
lifecycle DML; `PUBLIC`/`anon` cannot execute controlled or internal
functions; no untrusted role can `CREATE` on any `SECURITY DEFINER`
search_path schema. The temporary executor `CREATE` grant never exists in an
accepted database state.

## 4. Complete role, DML, and EXECUTE matrix

The following is the closed matrix after 012 for 001–011 objects plus 012
foundation ledgers. 013 applies the same privilege pattern to section 9B
tables without redesigning it. “Owner” means the migration owner; “executor”
means the applicable internal `NOLOGIN` role.

**Public catalog, evidence, taxonomy, and Phase 3 public context/registry
tables.**

- `PUBLIC`, `anon`, and `authenticated`: `SELECT` only where the existing
  public-read policy permits it; no `INSERT`, `UPDATE`, or `DELETE`.
- `service_role`: draft/proposed `INSERT` and nonterminal draft `UPDATE` only
  through explicitly listed administrative entry points; no direct DML.
- executor: DML required inside its entry points only.
- owner: maintenance DML, never an application credential.

Each executor has an executor-specific RLS policy on its table family with
`USING` and `WITH CHECK` requiring the exact `current_user`; without that
policy its `NOBYPASSRLS` entry point cannot write. No policy names
`service_role`, and executor policies do not make direct caller DML possible
because callers cannot assume an executor role.

This applies to the ten catalog tables; `source_identities`, `sources`,
`evidence_items`, `field_observations`, applicability scope/ledger/head tables,
`canonical_field_selections`, taxonomy tables,
`catalog_concept_mappings`, requirement rule tables,
`program_derived_features`, `student_feature_definitions`; all Fit registry
tables in 009; and `fit_context_claim_definitions`, `fit_context_claims`,
observations, selection history/head, and context mappings in 010.

**Student-owned Phase 2 and Fit intent tables.**

- `PUBLIC`/`anon`: no access.
- `authenticated`: owner-scoped `SELECT`; no DML.
- `service_role`: no direct DML; calls student draft-write/freeze/delete entry
  points.
- student executor: entry-point DML.
- owner: maintenance only.

This applies to `students`, `private.student_identities`,
`student_profile_versions` and every profile child,
`student_derived_feature_values`, all `fit_intent_*` tables, and
`private.fit_student_access_contexts` and
`private.student_lifecycle_audit` (no authenticated read).

**Eligibility and Fit evaluation lifecycle tables.**

- `PUBLIC`/`anon`: no access.
- `authenticated`: owner-scoped `SELECT`; no DML.
- `service_role`: no direct DML; calls start/assemble/seal/finalize functions.
- evaluation executor: entry-point DML.
- owner: maintenance only.

After 012 this applies to existing 008/011 evaluation objects only:
`eligibility_evaluations`, all 008 `eligibility_manifest_*` tables,
`eligibility_requirement_results`, `eligibility_course_matches`,
`eligibility_test_matches`, `fit_evaluations`, `fit_evaluation_methods`,
`private.fit_evaluation_assembly_authorizations`, every `fit_manifest_*`,
financial normalizations, input-domain states, dimension results, signals,
signal evidence, and dimension reasons.

After 013 the same DML/EXECUTE pattern extends, without redesign, to 013
tables: Eligibility v0.2 replay-pin, snapshot-scope/member/universe,
projection-result, projection-threshold, and negative-authority/scope tables.
012 must not name those tables in grants, anti-joins, or acceptance queries.

**EXECUTE.**

- `PUBLIC` and `anon`: no business-function execute.
- `authenticated`: only `current_user_owns_student(uuid)` and
  `current_user_owns_profile(uuid)`, both fixed-path read helpers.
- `service_role`: only named business entry points; no guard, validator,
  serializer, lock helper, audit-function, or (after 013) v0.2 fingerprint
  helper execute.
- executors: their entry points plus exact helper signatures required by those
  entry points.
- owner: all functions.

RLS remains defense in depth. Tests run `service_role` with hosted-style
`BYPASSRLS` and must still fail every prohibited direct write.

## 5. Security-significant GUC inventory and disposition

Every setting read or written by 001–011 and the shipped SQL tests is accounted
for:

1. `app.controlled_catalog_write` — directly exploitable for canonical
   selection and catalog mutation in 002; replaced by catalog executor identity.
2. `app.rule_set_controlled_write` — directly exploitable for rule-set terminal
   status in 007; replaced by catalog executor identity.
3. `app.evaluation_controlled_write` — directly exploitable for Eligibility
   completion in 008; replaced by evaluation executor identity.
4. `app.student_privacy_delete` — directly exploitable for deletion of frozen
   profile children, derived values, Eligibility rows, Fit intents, and Fit
   rows in 005, 006, 008, 010, and 011; replaced by a relational deletion
   authorization row plus student executor identity.
5. `app.fit_registry_controlled_write` — directly exploitable for registry
   verification/retirement in 009; replaced by catalog executor identity.
6. `app.fit_intent_controlled_write` — directly exploitable for intent freeze
   in 010; replaced by student executor identity.
7. `app.fit_context_controlled_write` — directly exploitable for context
   definition/observation review and retirement in 010; replaced by catalog
   executor identity.
8. `app.fit_context_mapping_controlled_write` — directly exploitable for
   context mapping initial and terminal states in 010; replaced by catalog
   executor identity.
9. `app.fit_context_selection_write` — directly exploitable for current/history
   selection writes in 010; replaced by catalog executor identity.
10. `app.fit_evaluation_controlled_write` — directly exploitable for Fit
    sealing/completion in 011; replaced by evaluation executor identity.
11. `request.jwt.claim.sub` — caller-influenced attribution in audit functions
    and `fit_evaluations.finalized_by`; it remains usable only as untrusted
    display attribution. Authorization uses `auth.uid()` only in owner-read
    helpers. Terminal actor columns use the authenticated identity passed
    through a trusted gateway claim only after owner/service authorization, or
    fall back to `session_user`; they never authorize DML.
12. `app.fit_evaluator_write` — appears only in test 003 and has no production
    reader in 001–011. It remains an explicit negative spoof fixture and grants
    nothing.

012 removes every production `current_setting('app....')` and
`set_config('app....')` branch. Transaction-local and session-level values,
including `on`, arbitrary text, and inherited pool residue, have no effect.

## 6. Deterministic lifecycle locks and two-session contract

012 adds
`private.lock_student_lifecycle(p_student_id uuid) returns void`. The lock
identity is the stable `students.student_id`, never a profile version,
intent-set, evaluation, or snapshot ID. 013 must not change that identity.

Every operation that can race a student’s frozen, replay, or privacy state
resolves `student_id` **without locking**, then calls this helper
**before acquiring any other advisory or row lock**.

**012 closed caller set:** `freeze_student_profile_version`;
`freeze_fit_intent_set`; `start_eligibility_evaluation`,
`seal_eligibility_evaluation_inputs`,
`finalize_eligibility_evaluation(uuid, eligibility_outcome)`;
`start_fit_evaluation`, `seal_fit_evaluation_inputs`,
`finalize_fit_evaluation`; `delete_student_data`; 008 manifest/result/match
writers; student mapping propose/review/retire; profile-child inserts; Fit
intent child inserts; and student derived-value appends. Catalog and source
paths do not take this lock.

**013 additive callers, same helper:** `start_eligibility_evaluation_v02`,
`seal_eligibility_evaluation_inputs_v02`,
`finalize_eligibility_evaluation_v02`; every `insert_eligibility_snapshot_*`
and `insert_eligibility_*_pin` writer. 013 does not replace the helper or
reorder 012 families.

The helper takes
`pg_advisory_xact_lock(hashtextextended('student-lifecycle:' ||
lower(p_student_id::text), 0))`, then locks the matching `students` row
`FOR UPDATE`; absence raises `23503`. That `students` row lock is the
correctness boundary shared by freeze, evaluation lifecycle, and privacy
deletion. Privacy deletion and evaluation finalization therefore serialize:
they cannot both hold the same `students` row lock.

After the helper returns, narrower row locks are acquired in this **exact
total order**. An operation skips a family it does not touch or that does not
yet exist; it never locks a later family before an earlier one, and never
locks a child before its parent in this list:

1. `student_profile_versions` of that student, ordered by `profile_version_id`
   ascending;
2. `fit_intent_sets` of that student, ordered by intent-set UUID ascending;
3. `eligibility_evaluations` of that student, then `fit_evaluations` of that
   student, each family ordered by evaluation UUID ascending;
4. evaluation-scoped domain/state rows of the target evaluation. After 012
   this family is only existing 011 `fit_input_domain_states`, ordered by
   domain-state UUID ascending. After 013 the same family also includes
   `eligibility_snapshot_scopes`, locked before Fit domain states, ordered by
   `scope_id` ascending. 013 does not change the relative order of families 1–3
   or 5;
5. remaining child rows (profile children, mappings, 008 manifests/results/
   matches, Fit manifest/result children), ordered by primary UUID ascending.
   After 013 this family also includes Eligibility v0.2 pin, universe,
   projection-result, and negative-authority children.

No student-owned path may lock a profile, intent set, evaluation, or child row
first. 012 tests skip absent 013 families.

### 6.1 Advisory locks are serialization hints only

`hashtextextended(..., 0)` returns a signed 64-bit value. Distinct texts can
collide. A collision may extra-block an unrelated student or object; it must
**never** decide which row is written. Advisory locks are not identity, not
uniqueness, and not a correctness boundary.

Correctness is exactly:

- parent/target `FOR UPDATE` (and `FOR KEY SHARE` where named);
- unique, exclusion, and foreign-key constraints;
- terminal-state guards;
- exact set-equality checks;
- mandatory revalidation of parent, head, state, and expected set after every
  lock is held.

The same rule applies to every advisory namespace in this plan. Two-session
tests that disable the advisory call (row locks still taken) must still reject
every invariant violation. Tests that force an advisory-key collision must
show only extra serialization, never a wrong head or lost update. 013 ordinal
tests use the same advisory-collision rule and must not redesign it.

### 6.2 Non-student lock protocols

- source revision: **no advisory lock**. Directly lock the
  `source_identities` parent row `FOR UPDATE`; read `current_source_id`; lock
  that current `sources` row `FOR KEY SHARE`; revalidate that it is still the
  parent head; insert the successor; update the parent head. The parent row
  lock is the correctness boundary.
- evidence scope: advisory-lock a 64-bit hash of the length-prefixed
  nine-part semantic key from section 7, insert-or-select by exact-key
  uniqueness, then lock the scope row and existing applicability head
  `FOR UPDATE`. Collision extra-blocks; the unique key and row locks decide
  the head.
- program lifecycle: advisory-lock `program_id`, then lock `programs` and its
  active `program_schools` rows ordered by UUID;
- mapping/rule/registry/context lifecycle: advisory-lock the object UUID,
  then lock its authoritative parent and lifecycle row `FOR UPDATE`;
- taxonomy release lifecycle (012): lock the `taxonomy_releases` row
  `FOR UPDATE`. 012 has no ordinal allocator;
- taxonomy release ordinal (013 only): lock the singleton allocator row in
  section 15.1 before the release row; no hash decides ordinal correctness.

Each function re-reads parent, head, state, and expected set after all locks.
Expected first-row/head races catch `unique_violation`, resolve the exact
semantic row, reacquire its row lock, and revalidate. The losing transaction
receives SQLSTATE `55000` and a stable object-specific error, not incidental
unique-violation authority.

**Deterministic winner/loser.** For one `student_id`, the winner is the
transaction that first acquires `students FOR UPDATE`. The loser blocks, then
revalidates: if the student is gone, `23503`; if the profile/intent is
`FROZEN` and the loser is a draft write, `55000`; if the evaluation is
`COMPLETED` or absent, `55000`; if deletion committed, finalize
fails closed. After 013 the same rule applies to snapshot writers. For one `source_identity_id`, the winner is the transaction
that first acquires the identity parent `FOR UPDATE`; the loser revalidates
the new head and fails `55000` if it still tries to supersede the stale head.

**Required two-session tests** (each asserts block/unblock plus terminal
SQLSTATE/constraint identity):

- 012: freeze profile vs freeze intent vs start Eligibility v0.1 vs start
  Fit vs delete, all on one `student_id` with distinct child IDs: every pair
  blocks on the same `students` row;
- 012: privacy deletion vs Eligibility v0.1 finalize and vs Fit finalize:
  they serialize; the winner commits; the loser revalidates and cannot
  complete a half-deleted evaluation;
- 013 additive: create snapshot vs delete, and privacy deletion vs
  `finalize_eligibility_evaluation_v02`, using the same first lock;
- session B revalidates both after A commits and after A rolls back;
- advisory collision of two distinct student IDs extra-blocks only;
- disabling the advisory call does not permit an invariant violation;
- concurrent source successors serialize on the identity parent and produce
  exactly one next revision number;
- reversed child UUID lists cannot deadlock because post-student locks follow
  the total order above.

## 7. Normalized evidence applicability ledger and head

012 adds one model, not parallel assertion/version mechanisms.

`evidence_items` remain immutable after insert. There is no evidence-revision
table. `evidence_id` is both the evidence-item identity and the evidence
revision identity. A changed excerpt, locator, cycle context, or retrieval
creates a new `evidence_id`; it never mutates the old item. Evidence already
referenced by observations keeps the original `evidence_id`.

`evidence_applicability_scopes` contains:
`scope_id uuid PK`, and the **nine-part current-head semantic key**, every
column `NOT NULL`:

| Dimension | Column | NULL semantics |
|---|---|---|
| evidence item/revision | `evidence_id uuid` | never null; identity = revision |
| subject record type | `record_type catalog_record_type` | never null |
| subject record ID | `record_id uuid` | never null |
| resolved program | `program_scope_key text` | canonical lowercase UUID of the resolved `program_id`, or the token `NOT_PROGRAM_SCOPED` |
| resolved program version | `program_version_scope_key text` | canonical lowercase UUID of the resolved `program_version_id`, or the token `NOT_VERSION_SCOPED` |
| field / fact-family | `field_name text` | never null; the catalog field is the fact-family |
| granularity | `granularity_scope applicability_granularity_scope` | never SQL null; absent = `UNSPECIFIED` |
| population | `population_scope_code applicability_population_scope` | never SQL null; absent = `UNSPECIFIED` |
| cycle | `cycle_scope_code text` | never SQL null; absent = `UNSPECIFIED`; otherwise exact uppercase NFC token `^[A-Z0-9][A-Z0-9._:-]{0,63}$` |

Nullable UUID copies `resolved_program_id` and `resolved_program_version_id`
exist only as documented FKs: they are null exactly when the corresponding
`*_scope_key` is `NOT_PROGRAM_SCOPED` / `NOT_VERSION_SCOPED`. They are **not**
part of the unique key. PostgreSQL `NULL = NULL` is never used for scope
identity.

`create_evidence_scope(evidence_id, record_type, record_id, field_name,
granularity, population, cycle)` does **not** take caller program/version IDs.
The invoker validator derives them from the catalog parent chain and writes
the canonical keys:

- `UNIVERSITY`, `SCHOOL` → `NOT_PROGRAM_SCOPED` / `NOT_VERSION_SCOPED`;
- `PROGRAM`, `PROGRAM_SCHOOL` → resolved `program_id`, `NOT_VERSION_SCOPED`;
- `PROGRAM_VERSION` → parent `program_id`, this `program_version_id`;
- `PROGRAM_ADMISSION`, `PROGRAM_PREREQUISITE`, `PROGRAM_COURSE`,
  `PROGRAM_COST`, `PROGRAM_DEADLINE` → parent version then parent program.

Mismatch between caller record and derived program/version fails closed.
Different cycle, population, granularity, fact-family (`field_name`),
program, or program version therefore cannot share one accidental head.

**Applicability disposition is not a scope-key column.** Disposition is the
payload of the unique current assertion (`REVIEWED_APPLICABLE`,
`REVIEWED_INAPPLICABLE`). One scope has exactly one current head; a new
review supersedes that head. Two dispositions cannot be concurrently current
for one nine-part key.

The three semantic scope enums/tokens are never SQL null:

- `applicability_granularity_scope` is exactly `UNSPECIFIED` plus the six
  existing `metric_granularity` labels; absent granularity is `UNSPECIFIED`;
- `applicability_population_scope` is exactly `UNSPECIFIED` plus the five
  existing `population_scope` labels; absent population is `UNSPECIFIED`;
- absent cycle is canonical text `UNSPECIFIED`.

`scope_digest` is SHA-256 over length-prefixed canonical UTF-8 values in this
order: evidence UUID, record type, record UUID, program_scope_key,
program_version_scope_key, field name, granularity, population, cycle. It is
an indexed comparison aid, not an identity or correctness boundary. A unique
constraint on the nine semantic columns makes the full current-head key
enforceable. All are non-null canonical values, so PostgreSQL null uniqueness
is not involved. Insert recomputes the digest and compares exact columns even
when hashes match.

`evidence_applicability_assertions` is append-only and contains
`assertion_id`, nullable `scope_id`, `applicability_status`
(`REVIEWED_APPLICABLE`, `REVIEWED_INAPPLICABLE`, `LEGACY_UNASSERTED`),
`asserted_by`, `asserted_at`, `rationale`,
`foundation_contract_release_code`, and nullable
`supersedes_assertion_id`. Reviewed statuses require `scope_id`;
`LEGACY_UNASSERTED` requires it null and is linked only from one historical
observation.

`evidence_applicability_heads` has `scope_id` primary key and unique
`assertion_id`. That primary key is the current-head representation: exactly
one current assertion per nine-part scope. It is writable only by
`review_evidence_applicability(scope_id, status, actor, rationale)`.
Supersession must reference the current assertion for the same `scope_id`.
The head lock and equality check prohibit two current assertions, cross-scope
supersession, and stale-head updates.

`field_observation_applicability` has `observation_id` PK/FK and
`assertion_id`. Post-012 `KNOWN` observations require a headed
`REVIEWED_APPLICABLE` assertion whose nine-part scope equals the observation
request, including derived program/version keys. A non-`KNOWN` observation may
omit evidence and assertion; if evidence is present it requires a reviewed
scope and exact equality.

The shared invoker validator resolves all ten `catalog_record_type` values to
the exact table and primary key, proves `record_id` exists, proves `field_name`
is a real non-generated column of that table, rejects identity/audit columns,
derives program/version keys, and verifies program-version, cycle, population,
and granularity consistency. It replaces ad hoc dynamic reference checks for
all prospective uses.

012 inserts exactly one `LEGACY_UNASSERTED` assertion and observation link per
pre-012 observation, preserving all old selections. No legacy row receives a
scope or head and no scope is inferred. New selection, rule verification,
Eligibility start, Fit manifest inclusion, or replay requiring authority
rejects `LEGACY_UNASSERTED`. Review creates a scope, assertion, and head; if the
claim value changed it also creates a new observation.

## 8. Immutable source identity and revision history

The existing `sources` table remains the revision table; it is not renamed.
012 adds
`source_identities(source_identity_id PK, canonical_publisher, current_source_id
UNIQUE NOT NULL DEFERRABLE, created_at)` and these immutable columns to
`sources`:
`source_identity_id`, `revision_number`, `supersedes_source_id`,
`revision_reason`, and `retrieval_content_hash`. Unique
`(source_identity_id, source_id)` supports the parent FK.

Each old source receives its own identity and revision 1. The existing
`sources_url_key` uniqueness is dropped. It is replaced by unique
`(source_identity_id, revision_number)` and unique non-null
`supersedes_source_id` (revision 1 has null `supersedes_source_id` and is
excluded from that unique index). A deferrable FK makes
`source_identities.current_source_id` reference a `sources` row of that same
identity through unique `(source_identity_id, source_id)`.

**Current-head representation.** A partial unique index
`UNIQUE (source_identity_id) WHERE is_current` on `sources` is **forbidden**:
it would require mutating old revisions when the head moves, contradicting
immutability. The enforceable current-head constraint is the unique non-null
parent pointer `source_identities.current_source_id`. One identity row has
exactly one current revision. That unique parent pointer is the current-head
uniqueness constraint; it is the PostgreSQL equivalent of a partial unique
index on children without mutating children.

`create_source_revision(source_identity_id,publisher,title,url,
reliability_tier,source_type,retrieval_content_hash,revision_reason)` directly
locks the identity parent `FOR UPDATE`. The new row must supersede exactly the
parent’s current source, use the same identity, have
`revision_number = current + 1`, and provide reason and SHA-256 content hash;
the function then advances `current_source_id` in the same transaction.
Callers cannot supply `supersedes_source_id` or revision number. A stale-head
or forked successor fails `55000` after revalidation.

Exactly one current head is therefore the single non-null parent pointer, not
a nullable `is_current` flag. Only the current row may be superseded. Unique
prior reference means one direct successor; strict increment plus same-identity
current-only supersession makes cycles and forks impossible. A deferred
constraint trigger verifies every identity has one reachable head, every
non-first revision reaches revision 1 in exactly `revision_number - 1` links,
and the head has no successor. The same URL may recur across revisions without
losing history.

After insert, every `sources` column is immutable, including publisher, title,
URL, reliability tier, source type, all revision columns, `created_at`, and
`updated_at`; 012 removes the source `set_updated_at` trigger. Corrections and
changed retrievals create a revision. Existing evidence continues to reference
the original `source_id` (the exact revision). After 013, Eligibility v0.2
pins store that `source_id` and never read
`source_identities.current_source_id`. 012 replay integrity uses the immutable
`sources` revision row itself and does not create pin tables.
Source identity/revision insertion is function mediated and serialized by the
direct parent-row lock; advisory locking is not used for source correctness.

Concurrent winner: the transaction that first holds the identity `FOR UPDATE`
inserts `current_revision_number + 1` and updates the parent head. The loser
blocks, re-reads the new head, and cannot insert a second row with that
revision number or a second successor of the old head.

## 9. Initial-state, terminal-transition, and immutable-pin controls

The inventory is partitioned. Section 9A is the complete 012 acceptance
inventory. Section 9B is 013-only. **No 9B row is a 012 acceptance
requirement.** 012 must not create 9B objects. 013 may `CREATE OR REPLACE`
only the named 012 signatures called out in 9B, preserving public identity
arguments, executor owner, callers, `search_path`, and lock identity.

Direct insert is closed-world on 012-hardened existing objects:

- catalog/context mappings and Fit context observations enter only `PROPOSED`;
- Phase 1 `field_observations` have no workflow status and enter only through
  the append-only observation function;
- rule sets, Fit registry/context definitions, and methods enter only `DRAFT`;
- profiles and Fit intent sets enter only `DRAFT` with null hash/time;
- Eligibility v0.1 and Fit evaluations enter only `BUILDING` with null
  008/011 fingerprints/results;
- canonical selection/history heads are never directly inserted;
- `REJECTED`, `VERIFIED`, `RETIRED`, `FROZEN`, and `COMPLETED` are reachable
  only through exact entry points.

Terminal transitions permit only:

- `DRAFT -> VERIFIED -> RETIRED`;
- `PROPOSED -> VERIFIED|REJECTED`, and `VERIFIED -> RETIRED`;
- `DRAFT -> FROZEN`;
- `BUILDING -> COMPLETED`.

Composite row-type arguments are typed PostgreSQL composites, not JSON
dispatch. **No terminal state is reachable by INSERT.** `REJECTED`,
`VERIFIED`, `RETIRED`, `FROZEN`, and `COMPLETED` never appear on an `INSERT`
row; guards reject those values at insert and the section 4 revokes make
direct insert impossible for runtime roles. `Direct DML` = `none` means all
runtime `INSERT`/`UPDATE`/`DELETE` on that family are revoked from `PUBLIC`,
`anon`, `authenticated`, and `service_role`.

Lock protocol is the **first lock plus the section 6 total order** for
student-owned families, or the named non-student protocol. Every row’s
function owner, callers, and signatures are entered literally in
`foundation_function_contracts`. After 012 that registry contains 9A only.

### 9A. 012 controlled entry points

Only functions operating on existing 001–011 objects or new 012 foundation
ledgers/primitives.

| Object | Initial state | Transition | Entry function | Owner | Caller | Direct DML | Lock protocol | Audit | Migration owner |
|---|---|---|---|---|---|---|---|---|---|
| `source_identities` / `sources` revisions | identity + revision 1 | current revision → new current revision | `create_source_identity(text,text,text,reliability_tier,text,text,text)`; `create_source_revision(uuid,text,text,text,reliability_tier,text,text,text)` | catalog executor | `service_role` | none | identity parent `FOR UPDATE` (revision path) | `audit_events` with identity/revision IDs | 012 |
| Applicability scopes/assertions/heads and `field_observations` | immutable observation; reviewed assertion only through review | current assertion → same-scope successor | `create_evidence_scope(uuid,catalog_record_type,uuid,text,applicability_granularity_scope,applicability_population_scope,text)`; `review_evidence_applicability(uuid,evidence_applicability_status,text,text)`; `create_field_observation(catalog_record_type,uuid,text,jsonb,knowledge_status,uuid,uuid,text,uuid)` | catalog executor | `service_role` | none | scope advisory, scope/head rows `FOR UPDATE` | `audit_events` | 012 |
| `canonical_field_selections` / catalog retirement | no head until selected | head replacement; active → retired | `select_field_observation(uuid,text)`; `accept_field_observation(uuid,text)`; `retire_catalog_record(catalog_record_type,uuid,text,text)` | catalog executor | `service_role` | none | catalog-record advisory + row `FOR UPDATE` | `audit_events` | 012 |
| Ten catalog record tables | unretired draft record | field selection; program completion; retirement | `create_university(universities)`; `create_school(schools)`; `create_program(programs)`; `create_program_school(program_schools)`; `create_program_version(program_versions)`; `create_program_admission(program_admissions)`; `create_program_prerequisite(program_prerequisites)`; `create_program_course(program_courses)`; `create_program_cost(program_costs)`; `create_program_deadline(program_deadlines)`; `complete_program_foundation(uuid)`; `replace_program_primary_school(uuid,uuid,text)`; `retire_catalog_record(catalog_record_type,uuid,text,text)` | catalog executor | `service_role` | none | record/program lock | `audit_events` | 012 |
| `taxonomy_releases` lifecycle (no ordinals) | 012 adds `DRAFT\|VERIFIED\|RETIRED`; existing `v0.1` backfilled `VERIFIED` | `DRAFT → VERIFIED → RETIRED` | `create_taxonomy_release(text,timestamptz,text)`; `verify_taxonomy_release(text,text)`; `retire_taxonomy_release(text,text)` | catalog executor | `service_role` | none | release row `FOR UPDATE` | `audit_events` | 012 |
| Taxonomy concepts/aliases/relationships (existing 004 text release FKs) | created against a `DRAFT` release | become usable when introducing release verifies; 012 retirement uses existing `retired_in_release` text | `create_taxonomy_concept(taxonomy_concepts)`; `create_taxonomy_alias(taxonomy_aliases)`; `create_taxonomy_relationship(taxonomy_relationships)`; `retire_taxonomy_concept(uuid,text,text)`; `retire_taxonomy_alias(uuid,text,text)`; `retire_taxonomy_relationship(uuid,text,text)` | catalog executor | `service_role` | none | release row then semantic row | `audit_events` | 012 |
| `catalog_concept_mappings` | `PROPOSED` | `PROPOSED → VERIFIED\|REJECTED`; `VERIFIED → RETIRED` | `propose_catalog_concept_mapping(catalog_concept_mappings)`; `review_catalog_concept_mapping(uuid,mapping_status,text,uuid)`; `retire_catalog_concept_mapping(uuid,text)` | catalog executor | `service_role` | none | mapping advisory + row | `audit_events` | 012 |
| `student_record_concept_mappings` | `PROPOSED` under draft profile | same mapping transitions before freeze; immutable after profile freeze | `propose_student_record_concept_mapping(student_record_concept_mappings)`; `review_student_record_concept_mapping(uuid,mapping_status,text,uuid)`; `retire_student_record_concept_mapping(uuid,text)` | student executor | `service_role` | none | student lifecycle, then mapping row | private student lifecycle audit, cascades on delete | 012 |
| Requirement rule set and node/source/mapping content | `DRAFT` | `DRAFT → VERIFIED → RETIRED` | `create_requirement_rule_set(program_requirement_rule_sets)`; `insert_requirement_node(program_requirement_nodes)`; `insert_requirement_node_source(program_requirement_node_sources)`; `insert_requirement_node_mapping(program_requirement_node_mappings)`; `verify_program_requirement_rule_set(uuid,text,uuid)`; `retire_program_requirement_rule_set(uuid,text)` | catalog executor | `service_role` | none | rule-set advisory + row | `audit_events` | 012 |
| Program/student derived history and feature definitions | append-only value; active definition | definition active → retired | `append_program_derived_feature(program_derived_features)`; `create_student_feature_definition(student_feature_definitions)`; `append_student_derived_feature_value(student_derived_feature_values)`; `retire_student_feature_definition(uuid)` | catalog/student executor by ownership | `service_role` | none | program lock or student lifecycle first | catalog audit or private cascading student audit | 012 |
| Student/profile and every profile child except mappings | profile `DRAFT` | draft edits; `DRAFT → FROZEN` | `create_student(uuid)`; `create_student_profile_version(uuid,integer)`; `insert_student_data_completeness(student_data_completeness)`; `insert_student_evidence_item(student_evidence_items)`; `insert_student_degree(student_degrees)`; `insert_student_course(student_courses)`; `insert_student_test_score(student_test_scores)`; `insert_student_experience(student_experiences)`; `insert_student_skill(student_skills)`; `insert_student_experience_skill(student_experience_skills)`; `insert_student_goal(student_goals)`; `insert_student_preference(student_preferences)`; `freeze_student_profile_version(uuid)` | student executor | `service_role` | none | student lifecycle first | private student lifecycle audit, cascades on delete | 012 |
| Student privacy closure | existing student | active → deleted + non-PII tombstone | `delete_student_data(uuid,text)` calling `private.close_student_owned_rows(uuid)` | student executor | `service_role` | none | student lifecycle first | tombstone only after closure | 012 |
| Fit registry definitions/methods/builds/reasons/financial definitions | `DRAFT` | `DRAFT → VERIFIED → RETIRED` | `insert_fit_contract_release(fit_contract_releases)`; `insert_fit_semantic_source_class(fit_semantic_source_classes)`; `insert_fit_evaluator_build(fit_evaluator_builds)`; `insert_fit_dimension_method(fit_dimension_methods)`; `insert_fit_method_source_class_policy(fit_method_source_class_policies)`; `insert_fit_mapping_relation_definition(fit_mapping_relation_definitions)`; `insert_fit_method_mapping_relation_policy(fit_method_mapping_relation_policies)`; `insert_fit_signal_type(fit_signal_types)`; `insert_fit_method_input_policy(fit_method_input_policies)`; `insert_fit_method_program_field_policy(fit_method_program_field_policies)`; `insert_fit_reason_definition(fit_reason_definitions)`; `insert_fit_financial_normalization_method(fit_financial_normalization_methods)`; `verify_fit_definition(text,uuid,text,uuid)`; `retire_fit_definition(text,uuid,text)` | catalog executor | `service_role` | no runtime DML; 009 seed remains migration-owned history | registry advisory + typed row | `audit_events` | 012 |
| Fit intent set/declarations/typed children/access contexts | intent set `DRAFT` | draft inserts; `DRAFT → FROZEN` | `create_fit_intent_set(uuid,integer)`; `insert_fit_intent_declaration(fit_intent_declarations)`; `insert_fit_intent_validation_issue(fit_intent_validation_issues)`; `insert_fit_intent_taxonomy_target(fit_intent_taxonomy_targets)`; `insert_fit_intent_location_constraint(fit_intent_location_constraints)`; `insert_fit_intent_delivery_constraint(fit_intent_delivery_constraints)`; `insert_fit_intent_financial_constraint(fit_intent_financial_constraints)`; `insert_fit_intent_duration_constraint(fit_intent_duration_constraints)`; `insert_fit_intent_program_feature_constraint(fit_intent_program_feature_constraints)`; `insert_fit_student_access_context(private.fit_student_access_contexts)`; `freeze_fit_intent_set(uuid)` | student executor | `service_role` | none | student lifecycle first | private student lifecycle audit, cascades on delete | 012 |
| Fit context definitions/observations/selections/mappings | definition `DRAFT`; observation/mapping `PROPOSED` | definition verify/retire; observation verify/reject/retire; selection head replace; mapping verify/reject/retire | `insert_fit_context_claim_definition(fit_context_claim_definitions)`; `insert_fit_context_claim(fit_context_claims)`; `insert_fit_context_claim_observation(fit_context_claim_observations)`; `insert_fit_context_concept_mapping(fit_context_concept_mappings)`; `verify_fit_context_definition(uuid,text,uuid)`; `retire_fit_context_definition(uuid,text)`; `review_fit_context_observation(uuid,fit_claim_workflow_status,text,text)`; `select_fit_context_claim_observation(uuid,uuid,knowledge_status,text)`; `review_fit_context_mapping(uuid,mapping_status,text,uuid,text)` | catalog executor | `service_role` | none | context claim/definition lock | `audit_events` | 012 |
| Eligibility v0.1 evaluations, 008 manifests, results, matches | `BUILDING`; `input_schema_version = 'eligibility-v0.1'` | build → sealed inputs → `COMPLETED` under the frozen 008 semantic contract | `start_eligibility_evaluation(uuid,uuid,text,text,text,text)`; `insert_eligibility_manifest_degree(eligibility_manifest_degrees)`; `insert_eligibility_manifest_course(eligibility_manifest_courses)`; `insert_eligibility_manifest_test_score(eligibility_manifest_test_scores)`; `insert_eligibility_manifest_student_mapping(eligibility_manifest_student_mappings)`; `insert_eligibility_manifest_completeness(eligibility_manifest_completeness)`; `insert_eligibility_manifest_student_evidence(eligibility_manifest_student_evidence)`; `insert_eligibility_manifest_catalog_source(eligibility_manifest_catalog_sources)`; `insert_eligibility_manifest_catalog_mapping(eligibility_manifest_catalog_mappings)`; `insert_eligibility_manifest_taxonomy_concept(eligibility_manifest_taxonomy_concepts)`; `insert_eligibility_requirement_result(eligibility_requirement_results)`; `insert_eligibility_course_match(eligibility_course_matches)`; `insert_eligibility_test_match(eligibility_test_matches)`; `seal_eligibility_evaluation_inputs(uuid)`; `finalize_eligibility_evaluation(uuid, eligibility_outcome)` | evaluation executor | `service_role` | none | student lifecycle first, then profile, evaluation, children per §6 | private student lifecycle audit, cascades on delete | 012 |
| Fit evaluation, assembly authorization/manifests/results | `BUILDING` | build → sealed inputs → `COMPLETED` | `start_fit_evaluation(uuid,uuid,uuid,text,uuid,uuid,uuid,uuid)`; `authorize_fit_evaluation_assembly(uuid,text)`; composite writers `insert_fit_evaluation_method(fit_evaluation_methods)`, `insert_fit_manifest_item(fit_manifest_items)`, `insert_fit_manifest_intent_declaration(fit_manifest_intent_declarations)`, `insert_fit_manifest_student_access_context(fit_manifest_student_access_contexts)`, `insert_fit_manifest_phase2_goal(fit_manifest_phase2_goals)`, `insert_fit_manifest_phase2_preference(fit_manifest_phase2_preferences)`, `insert_fit_manifest_phase2_course(fit_manifest_phase2_courses)`, `insert_fit_manifest_phase2_completeness(fit_manifest_phase2_completeness)`, `insert_fit_manifest_phase2_mapping(fit_manifest_phase2_mappings)`, `insert_fit_manifest_catalog_observation(fit_manifest_catalog_observations)`, `insert_fit_manifest_catalog_mapping(fit_manifest_catalog_mappings)`, `insert_fit_manifest_taxonomy_concept(fit_manifest_taxonomy_concepts)`, `insert_fit_manifest_context_claim_selection(fit_manifest_context_claim_selections)`, `insert_fit_manifest_context_mapping(fit_manifest_context_mappings)`, `insert_fit_manifest_student_field_use(fit_manifest_student_field_uses)`, `insert_fit_financial_normalization(fit_financial_normalizations)`, `insert_fit_manifest_financial_normalization(fit_manifest_financial_normalizations)`, `insert_fit_input_domain_state(fit_input_domain_states)`, `insert_fit_dimension_result(fit_dimension_results)`, `insert_fit_signal(fit_signals)`, `insert_fit_signal_evidence(fit_signal_evidence)`, `insert_fit_dimension_reason(fit_dimension_reasons)`; `seal_fit_evaluation_inputs(uuid)`; `finalize_fit_evaluation(uuid)` | evaluation executor | `service_role` | none | student lifecycle first, then profile, intent, evaluation, children per §6 | private student lifecycle audit, cascades on delete | 012 |

`finalize_eligibility_evaluation(uuid, eligibility_outcome)` remains the 008
v0.1 historical API. 012 hardens authorization, DML, concurrency,
immutability, and security only. It does not drop `outcome`, derive
projections, or accept v0.2 evaluations.

### 9B. 013 Eligibility v0.2 entry points

013 installs these objects and signatures. None are required to accept 012.
Inside 013, ordinal columns and backfill commit before any
`CREATE OR REPLACE` of 012 taxonomy or rule-verification signatures, and pin
tables exist before `start_eligibility_evaluation_v02`.

| Object | Initial state | Transition | Entry function | Owner | Caller | Direct DML | Lock protocol | Audit | Migration owner |
|---|---|---|---|---|---|---|---|---|---|
| Taxonomy ordinal allocator singleton | singleton row exists after 013 backfill (`next_ordinal = 2` after `v0.1` occupies ordinal 1) | next ordinal allocation only | no direct public function; allocation is inside the 013 replacement of `create_taxonomy_release` | catalog executor (via create) | `service_role` via `create_taxonomy_release` | none | `private.taxonomy_release_ordinal_allocator` singleton `FOR UPDATE` first, then release row | `audit_events` on the created release | 013 |
| `taxonomy_releases` ordinal columns | existing 012 lifecycle rows | 013 backfills immutable positive unique `release_ordinal`; later creates allocate the next ordinal | 013 `CREATE OR REPLACE` of `create_taxonomy_release(text,timestamptz,text)` and `verify_taxonomy_release(text,text)` (same identity arguments, owner, callers, path) | catalog executor | `service_role` | none | allocator `FOR UPDATE`, then release row `FOR UPDATE`; post-lock `max(ordinal)+1` revalidation | `audit_events` | 013 |
| Concept/alias/relationship ordinal validity | 013 adds `introduced_release_ordinal` / `retired_release_ordinal` | create against `DRAFT`; retire-at-release effective on verify | 013 `CREATE OR REPLACE` of the 012 taxonomy create/retire signatures; no new public names | catalog executor | `service_role` | none | release row then semantic row | `audit_events` | 013 |
| Projected `AT_LEAST` thresholds | written at rule verification | immutable after verify | 013 `CREATE OR REPLACE` of `verify_program_requirement_rule_set(uuid,text,uuid)` writes `requirement_group_projection_thresholds` and checks active-at-release ordinals | catalog executor | `service_role` | none | rule-set advisory + row | `audit_events` | 013 |
| Eligibility v0.2 evaluation start | `BUILDING`; `input_schema_version = 'eligibility-v0.2'` | start only | `start_eligibility_evaluation_v02(uuid,uuid,text,text,text,text)` | evaluation executor | `service_role` | none | student lifecycle first, then profile, evaluation per §6 | private student lifecycle audit | 013 |
| Eligibility v0.2 replay pins | append-only under `BUILDING` | insert then immutable | `insert_eligibility_rule_set_pin(eligibility_rule_set_pins)`; `insert_eligibility_rule_node_pin(eligibility_rule_node_pins)`; `insert_eligibility_rule_node_source_pin(eligibility_rule_node_source_pins)`; `insert_eligibility_catalog_selection_pin(eligibility_catalog_selection_pins)`; `insert_eligibility_catalog_observation_pin(eligibility_catalog_observation_pins)`; `insert_eligibility_catalog_mapping_pin(eligibility_catalog_mapping_pins)`; `insert_eligibility_student_mapping_pin(eligibility_student_mapping_pins)`; `insert_eligibility_taxonomy_concept_pin(eligibility_taxonomy_concept_pins)`; `insert_eligibility_completeness_pin(eligibility_completeness_pins)` | evaluation executor | `service_role` | none | student lifecycle first, then evaluation, children per §6 | private student lifecycle audit, cascades on delete | 013 |
| Eligibility v0.2 domain snapshots / universes | created at assembly | freeze at seal | `insert_eligibility_snapshot_scope(eligibility_snapshot_scopes)`; `insert_eligibility_snapshot_degree(eligibility_snapshot_degrees)`; `insert_eligibility_snapshot_course(eligibility_snapshot_courses)`; `insert_eligibility_snapshot_test_score(eligibility_snapshot_test_scores)`; `insert_eligibility_snapshot_mapping_universe(eligibility_snapshot_mapping_universe)` | evaluation executor | `service_role` | none | student lifecycle first, then evaluation, snapshot, children per §6 | private student lifecycle audit, cascades on delete | 013 |
| Eligibility v0.2 seal | sealed inputs | `BUILDING` sealed → ready for v0.2 finalize | `seal_eligibility_evaluation_inputs_v02(uuid)` | evaluation executor | `service_role` | none | student lifecycle first | private student lifecycle audit | 013 |
| Eligibility v0.2 outcome-deriving finalizer and fingerprints | `COMPLETED` with derived projections/outcome | sealed → `COMPLETED`; SQL derives projections, outcome, and SHA-256 fingerprints | `finalize_eligibility_evaluation_v02(uuid)`; internal invoker helpers `private.canonical_eligibility_v02_input_fingerprint(uuid)` and `private.canonical_eligibility_v02_result_fingerprint(uuid)` (EXECUTE only to evaluation executor) | evaluation executor | `service_role` on the finalizer only | none | student lifecycle first, then profile, evaluation, snapshot, children per §6 | private student lifecycle audit, cascades on delete | 013 |
| Negative-authority / projection results | SQL-created at finalize | insert only by v0.2 finalizer | no caller insert function; `finalize_eligibility_evaluation_v02` writes `eligibility_negative_fact_authorizations`, `eligibility_negative_authorization_scopes`, and `eligibility_requirement_projection_results` | evaluation executor | none (finalizer only) | none | held under the finalizer’s §6 locks | private student lifecycle audit, cascades on delete | 013 |
| Privacy deletion 013 extension | 012 outer unchanged | extend closed-set anti-join | 013 `CREATE OR REPLACE` of `private.close_student_owned_rows(uuid)` (same identity arguments; not a public API) | migration-owner invoker helper | student executor via `delete_student_data` | none | same student lifecycle lock as 012 | tombstone only after extended closure | 013 |

Every 9A and 9B signature is entered literally in
`foundation_function_contracts`; no wildcard grant, variadic function,
dynamic table name, or generic JSON dispatch exists; `jsonb` appears only for
an existing typed canonical-value column. Composite types in the migration
use their schema-qualified `public.<type>` or `private.<type>` identity even
where the table omits that visual prefix. 9A is the 012 normative runtime
mutation path. 9B is the 013 normative runtime mutation path. An object
absent from both has no controlled runtime mutation path.

Catalog/registry events use existing `audit_events` through one
migration-owner invoker trigger. 012 adds
`private.student_lifecycle_audit(event_id uuid PK, student_id uuid FK ON
DELETE CASCADE, object_type text, object_id uuid, event_code text, actor text,
occurred_at timestamptz)` for student/profile/intent/evaluation events. It has
no public read grant, is writable only by the audit trigger, and is deleted by
privacy closure before the non-linkable tombstone. Every successful controlled
transition inserts exactly one audit row in the same transaction; failed
transitions insert none.

Terminal payload, identity, actor, evidence, contract, taxonomy, source,
manifest, method, evaluator-build, and created-at fields are immutable.
Retirement may change only status, `retired_at`, and `retirement_reason`.
Rejected/retired rows are fully immutable.

012 start/finalize of Eligibility v0.1 records the immutable 008 identities
already stored on `eligibility_evaluations` and requires those objects to be
currently active at start. 012 does not create v0.2 pin tables. 013 start
copies mutable semantics into pin tables under the section 6 lock.
Finalization of a v0.2 evaluation validates pins and set equality; it does
not fail because a pinned mapping or definition was retired after start. New
starts may not use the retired object. This separates 013 replay pins from
current authority without changing historical v0.1 evaluations.

## 10. Program completeness and exact primary school

There is no primary-school exception table.

012 adds `program_foundation_state` enum `DRAFT|COMPLETE` and
`programs.foundation_state NOT NULL`. Existing rows are backfilled
deterministically: `COMPLETE` only if they have exactly one active
`PRIMARY_ADMINISTRATIVE` relationship in the same university; otherwise
`DRAFT`. The MSQE row becomes `COMPLETE` without changing an existing column.

New programs enter `DRAFT`. `complete_program_foundation(program_id)` is the
only `DRAFT -> COMPLETE` path and requires exactly one active primary.
`active_status = ACTIVE` is permitted only for `COMPLETE`. Every non-retired
`COMPLETE` program must have exactly one active primary, irrespective of
`active_status`; there is no primary-school exemption.

The existing partial unique index supplies “at most one.” Deferred constraint
triggers on `programs` and `program_schools` supply “at least one” at commit,
checking old and new program IDs. The program lock permits atomic primary
replacement. A complete program must first return to no earlier state—it
cannot—so retiring its sole primary requires either same-transaction
replacement or retirement of the program. No joint school is promoted
automatically.

## 11. Derived-feature history decision

The policy is decided:

- `program_derived_features` is append-only; update/delete always fail.
- 012 adds nullable `supersedes_derived_feature_id`; it must reference the same
  program version and feature name and cannot already be superseded.
- `student_derived_feature_values` remains append-only except controlled
  privacy deletion.
- `student_feature_definitions` is editable only while unreferenced. After its
  first value, semantic fields and contracts are immutable; retirement is
  function-mediated and changes only `retired_at`.
- A correction always creates a new definition version or value row.
- Neither derived-feature family becomes an Eligibility v0.1/v0.2 input or a
  canonical source fact.

## 12. Eligibility v0.2 closed-world absence authority

### 12.1 Exact normalized replay pins

013 does not depend on a mutable row’s later state. Historical replay reads
only the pin tables below plus immutable 012 revision/assertion/observation
rows referenced by those pins. Replay **must not** consult
`source_identities.current_source_id`, `evidence_applicability_heads`,
`canonical_field_selections`, live `mapping_status`, live
`retired_release_ordinal`, or any other current head.

All pin tables are append-only, keyed first by `evaluation_id`, and guarded
by the evaluation lifecycle and the section 6 student lock. At start/assembly,
SQL copies every mutable semantic under that lock. Finalization validates pin
referential integrity and exact manifest equality, not current active status.
New starts require current `VERIFIED`/active authority. Retirement after start
cannot reinterpret the evaluation; completed v0.1 rows receive no synthetic
pins.

**FK vs pin-at-use strategy for every required item:**

| Required pin | Storage | Strategy |
|---|---|---|
| Canonical field observation ID | `eligibility_rule_node_source_pins.field_observation_id` | Immutable FK to `field_observations`. Observations are append-only after 012. |
| Canonical selection identity/state at use | `eligibility_catalog_selection_pins(evaluation_id, record_type, record_id, field_name, observation_id, selected_at_pin, selected_by_pin, PK(evaluation_id, record_type, record_id, field_name))` | **Pin-at-use values.** Current `canonical_field_selections` is a mutable head. Replay uses the pin, never the live head. `observation_id` is an immutable FK to the selected observation. |
| Evidence applicability assertion at use | `eligibility_rule_node_source_pins.applicability_assertion_id` | Immutable FK to `evidence_applicability_assertions` (append-only). |
| Evidence applicability head at use | `eligibility_rule_node_source_pins.applicability_head_assertion_id_at_pin` | **Pin-at-use UUID copy** of the `evidence_applicability_heads.assertion_id` that was current at pin time. Must equal `applicability_assertion_id`. Replay does not read the live head table. |
| Applicability scope at use | `eligibility_rule_node_source_pins.applicability_scope_id` plus copied `knowledge_status_at_pin` | Immutable FK to the nine-part scope row; status on the observation is copied. |
| Exact source revision ID | `eligibility_rule_node_source_pins.source_id` and `eligibility_manifest_catalog_sources.source_id`; also copied `source_identity_id`, `source_revision_number`, `retrieval_content_hash` on `eligibility_catalog_observation_pins` below | Immutable FK to `sources.source_id` (the revision). **Never** store or follow `current_source_id`. |
| Catalog mapping ID | `eligibility_catalog_mapping_pins.catalog_mapping_id` | Immutable FK to `catalog_concept_mappings`. |
| Student mapping ID | `eligibility_student_mapping_pins.student_mapping_id` | Immutable FK to `student_record_concept_mappings` (frozen profile child). |
| Mapping relation at use | catalog: `eligibility_catalog_mapping_pins.relation_at_pin`; student: `eligibility_student_mapping_pins.relation_at_pin` | **Pin-at-use copy.** Catalog copies `catalog_mapping_relation`. Student mappings have no relation column in 005; pin the closed token `STUDENT_CONCEPT_ASSOCIATION`. Replay never reads live `relation`. |
| Mapping status at use | `status_at_pin mapping_status` on both mapping pin tables | **Pin-at-use copy.** Live `mapping_status` can later become `RETIRED`. Replay uses `status_at_pin` only. |
| Taxonomy release ordinal | `eligibility_rule_set_pins.taxonomy_release_ordinal` and `eligibility_evaluations` copied ordinal | **Pin-at-use bigint copy** plus immutable release-code FK. |
| Concept introduced/retired validity at use | `eligibility_taxonomy_concept_pins.introduced_release_ordinal` (NOT NULL) and `retired_release_ordinal` (nullable copy) | **Pin-at-use copies.** Live concept retirement ordinals can change when a later release verifies. Validity at replay is `introduced <= pin_ordinal AND (retired IS NULL OR pin_ordinal < retired)` using **pinned** ordinals only. |
| Completeness authority | `eligibility_completeness_pins` copies `completeness_id`, `scope_id`, `domain`, `completeness`, `explanation` | Frozen-profile completeness row is immutable after freeze: FK to `completeness_id` **and** copied scalar values. Replay uses the copies. |
| Domain snapshot identity | `eligibility_snapshot_scopes.scope_id` | First-class snapshot identity created at assembly; immutable after seal. Membership tables reference `scope_id`. |
| Rule-set version/tree | `eligibility_rule_set_pins` + `eligibility_rule_node_pins` + threshold pins | Immutable FK to `rule_set_id` plus copied `rule_set_version`, schema/engine versions, and full node tree. Node payload is immutable after 012 verify; copies still taken so replay does not join live rule tables for semantics. |
| Engine/schema/contract versions | `eligibility_evaluations` columns `input_schema_version`, `result_semantics_version`, `canonicalization_version`, `evaluator_*`, `contract_release_code` plus rule-set pin versions | **Copied onto the evaluation row at start.** v0.2 start writes `eligibility-v0.2` / `eligibility-v0.2-c14n1`; v0.1 rows remain `eligibility-v0.1`. |

**Pin table shapes:**

- `eligibility_rule_set_pins(evaluation_id PK, rule_set_id,
  program_version_id, rule_set_version, taxonomy_release_code,
  taxonomy_release_ordinal, rule_schema_version, engine_contract_version,
  verification_evidence_id, verified_by, verified_at)`;
- `eligibility_rule_node_pins(evaluation_id, rule_node_id, parent_node_id,
  sort_order, node_kind, group_operator, minimum_children, predicate_kind,
  requirement_strength, requirement_semantics, target_concept_id,
  explanation_template, PK(evaluation_id,rule_node_id))`;
- `eligibility_rule_node_source_pins(evaluation_id, rule_node_id,
  field_observation_id, source_id, applicability_assertion_id,
  applicability_head_assertion_id_at_pin, applicability_scope_id,
  knowledge_status_at_pin,
  PK(evaluation_id,rule_node_id,field_observation_id))`;
- `eligibility_catalog_observation_pins(evaluation_id, field_observation_id,
  source_id, source_identity_id, source_revision_number,
  retrieval_content_hash, evidence_id, record_type, record_id, field_name,
  canonical_value, knowledge_status, program_scope_key,
  program_version_scope_key, granularity_scope, population_scope_code,
  cycle_scope_code, PK(evaluation_id, field_observation_id))` — scalar copies
  of the immutable observation/source/scope rows so canonicalization does not
  join live heads;
- `eligibility_catalog_selection_pins` as in the strategy table;
- `eligibility_catalog_mapping_pins(evaluation_id,catalog_mapping_id,
  record_type,record_id,concept_id,relation_at_pin,method,confidence,
  model_version, verification_evidence_id,reviewed_by,reviewed_at,
  status_at_pin, PK(evaluation_id,catalog_mapping_id))`;
- `eligibility_student_mapping_pins(evaluation_id,student_mapping_id,
  profile_version_id,record_type,student_record_id,concept_id,
  relation_at_pin,method, confidence,model_version,student_evidence_id,
  reviewed_by,reviewed_at, status_at_pin,PK(evaluation_id,student_mapping_id))`;
- `eligibility_taxonomy_concept_pins(evaluation_id,concept_id,canonical_key,
  concept_kind,introduced_release_ordinal,retired_release_ordinal,
  PK(evaluation_id,concept_id))`;
- `eligibility_completeness_pins(evaluation_id,completeness_id,scope_id,
  domain,completeness,explanation,PK(evaluation_id,completeness_id))`;
- existing degree/course/test/evidence manifests remain identity FKs because
  the frozen profile rows are immutable; their exact scalar fields are copied
  into canonicalization from those frozen rows, not from a second semantic
  table and not from any later profile;
- evaluator name/version/build hash, profile snapshot hash, contract release,
  result-semantics version, taxonomy release/ordinal, and canonicalization
  version remain immutable columns of `eligibility_evaluations`.

`insert_eligibility_catalog_observation_pin` and
`insert_eligibility_catalog_selection_pin` are additional section 9B entry
points owned by the evaluation executor. They are not 012 objects.

### 12.2 First-class completeness scopes

`eligibility_snapshot_scopes` has:
`scope_id uuid PK`, `evaluation_id`, `profile_version_id`,
`scope_kind` (`GLOBAL_PROFILE`, `EDUCATION_CONTEXT`,
`UNASSIGNED_CONTEXT`), nullable `education_context_id`, `domain`,
`completeness_id`, `completeness`, and unique
`(evaluation_id,scope_kind,education_context_id,domain) NULLS NOT DISTINCT`.

Shape is closed:

- `GLOBAL_PROFILE` requires null context and owns
  `EDUCATION_HISTORY`, `TEST_HISTORY`, `EXPERIENCE_HISTORY`,
  `SKILL_HISTORY`, `PREFERENCES`, and `GOALS`;
- `EDUCATION_CONTEXT` requires a degree ID from the exact profile and owns
  `COURSE_HISTORY` and `COURSE_MAPPING`;
- `UNASSIGNED_CONTEXT` requires null context and owns `COURSE_HISTORY` and
  `COURSE_MAPPING` for courses whose `student_degree_id` is null.

`UNASSIGNED_CONTEXT` always exists, even when empty. It replaces the old
“global course scope only when there are no degrees” behavior. The three kinds
are normalized identities; no semantic scope relies on ordinary nullable-key
uniqueness or on `NULL = NULL`.

Membership is a closed partition:

- a degree belongs only to `GLOBAL_PROFILE`/`EDUCATION_HISTORY`;
- a course with non-null `student_degree_id` belongs only to that degree’s
  `EDUCATION_CONTEXT`/`COURSE_HISTORY` (and its mappings to `COURSE_MAPPING`);
- a course with null `student_degree_id` belongs only to
  `UNASSIGNED_CONTEXT`;
- a test belongs only to `GLOBAL_PROFILE`/`TEST_HISTORY`;
- no record belongs to two scopes; a null-context course is never treated as
  global academic history.

Normalized membership tables are:
`eligibility_snapshot_degrees(scope_id,student_degree_id)`,
`eligibility_snapshot_courses(scope_id,student_course_id)`,
`eligibility_snapshot_test_scores(scope_id,student_test_score_id)`, and
`eligibility_snapshot_mapping_universe(scope_id,student_mapping_id,
universe_role)`, where `universe_role` is `AUTHORITATIVE` or `LIMITING`.

### 12.3 Exact universes and negative authority

For degree/course predicates, two disjoint universes are reconstructed from
pins, never from live mapping heads:

- **Decision-authoritative mapping set:** exactly the pinned student mappings
  with `status_at_pin = VERIFIED`, `relation_at_pin` in the closed allowed
  set, whose mapped record is a member of the scope, whose concept is valid
  at the **pinned** taxonomy ordinal, and whose evidence ID is in the
  student-evidence manifest. Only this set may satisfy a mapped predicate.
- **Limiting / non-authoritative provenance:** exactly the pinned student
  mappings with `status_at_pin = PROPOSED` for the same record set and
  taxonomy-valid target concept space. Proposals cannot satisfy; their
  presence blocks `NOT_SATISFIED` and forces `UNKNOWN`.
- `REJECTED` and `RETIRED` (`status_at_pin`) mappings are neither
  authoritative nor limiting and **must not** appear in either universe.
- Retired-after-start live status is irrelevant; `status_at_pin` is used.

Catalog mapped predicates (rule-node catalog mappings) use the analogous
partition over `eligibility_catalog_mapping_pins`: `status_at_pin = VERIFIED`
is decision-authoritative; `PROPOSED` is limiting; `REJECTED`/`RETIRED` are
excluded.

The evaluation’s **authoritative mapping manifest** is
`eligibility_manifest_student_mappings` restricted to mappings whose pin
status is `VERIFIED` (and the analogous catalog manifest). The **frozen
authoritative mapping universe** is
`eligibility_snapshot_mapping_universe` rows with `universe_role =
AUTHORITATIVE`. Finalization requires bidirectional `EXCEPT` equality of
those two sets. A negative result cannot omit a `VERIFIED` mapping that would
satisfy the predicate: omitting it makes the two sets unequal and
finalization fails. The same bidirectional equality is required for the
limiting universe versus pinned `PROPOSED` mappings, and for catalog
authoritative/limiting sets versus catalog mapping pins/manifests.

Finalization also performs bidirectional `EXCEPT` equality for: all profile
degrees against degree snapshot membership; all courses in each degree and all
unassigned courses against their respective scope; all profile tests against
the global test scope; every required completeness scope against
`eligibility_snapshot_scopes`; and every scope/member row back against its
expected base universe. Omission, addition, duplicate ownership, or
cross-scope membership fails.

**Negative predicates — closed world, explicit:**

Course absence is `NOT_SATISFIED` only when every `EDUCATION_CONTEXT` and the
`UNASSIGNED_CONTEXT` is `COMPLETE` for both `COURSE_HISTORY` and
`COURSE_MAPPING`, all equalities hold, no completed course has an
authoritative target mapping, and no limiting target mapping exists. Test
absence requires global `TEST_HISTORY=COMPLETE`, exact test equality, and no
matching test. Degree absence requires global `EDUCATION_HISTORY=COMPLETE`,
exact degree equality, no completed/in-progress degree with an authoritative
target mapping, and no limiting target mapping. Missing
`UNASSIGNED_CONTEXT`, a null-context course parked in an education scope, or
a `VERIFIED` mapping omitted from the authoritative universe makes the proof
illegal. All other cases are `UNKNOWN`.

`eligibility_negative_fact_authorizations(evaluation_id,rule_node_id,domain,
proof_version,created_at,PK(evaluation_id,rule_node_id))` is inserted only by
the finalizer. Its child
`eligibility_negative_authorization_scopes(evaluation_id,rule_node_id,scope_id)`
must equal the complete set of scopes used by the proof.

## 13. Exact Eligibility v0.2 projection and outcome

Each leaf has one class:

- ordinary hard: `strength=HARD`, `semantics=ORDINARY`;
- conditional hard: `strength=HARD`,
  `semantics=EXPLICIT_CONDITIONAL`;
- soft: `strength=SOFT`; 013 rejects `SOFT + EXPLICIT_CONDITIONAL`.

013 adds a four-state `eligibility_projection_value` union:
`SATISFIED`, `NOT_SATISFIED`, `UNKNOWN`, `ABSENT`.
`ABSENT` means the subtree has no participant in that projection; it is never
stored in the existing three-state leaf/result column.

The five projections are:

- `FULL`: every leaf with its actual value;
- `ORDINARY_BARRIER`: the normative **ordinary-hard decision projection**;
  soft leaves become `ABSENT` and explicit-conditional hard leaves are
  substituted with `SATISFIED`, preserving tree topology and asking whether an
  unavoidable ordinary-hard barrier remains;
- `CONDITIONAL_HARD`: all hard leaves at actual values, soft leaves `ABSENT`;
  this is the conditional-current decision projection and deliberately retains
  ordinary leaves so mixed tree topology is not lost;
- `CONDITIONAL_ONLY`: only explicit-conditional hard leaves, for explanation;
- `SOFT_EXPLANATION`: only soft leaves, for explanation.

There is no separate object called “ordinary-hard projection”:
`ORDINARY_BARRIER` is its fixed persisted name. Explicit conditional means a
verified, officially stated, remediable hard condition. It is never soft and
never admission probability. A failed conditional can produce
`CONDITIONALLY_ELIGIBLE` only when `ORDINARY_BARRIER` is `SATISFIED` or
`ABSENT`; this interpretation is frozen in `eligibility-v0.2`.

Executable operator rules over four-state children. `ABSENT` means this
subtree has zero descendants belonging to **this** projection. It is not
`SATISFIED`, `NOT_SATISFIED`, `UNKNOWN`, or knowledge-status
`NOT_APPLICABLE`.

Projection of a leaf (separate for each class):

| Leaf class | `FULL` | `ORDINARY_BARRIER` (ordinary-hard) | `CONDITIONAL_HARD` | `CONDITIONAL_ONLY` | `SOFT_EXPLANATION` |
|---|---|---|---|---|---|
| ordinary hard (`HARD`+`ORDINARY`) | actual | actual | actual | `ABSENT` | `ABSENT` |
| conditional hard (`HARD`+`EXPLICIT_CONDITIONAL`) | actual | substituted `SATISFIED` | actual | actual | `ABSENT` |
| soft (`SOFT`) | actual | `ABSENT` | `ABSENT` | `ABSENT` | actual |

Groups apply the operator to **already-projected** children.

**ALL after discarding `ABSENT` children.** If none remain → `ABSENT`.
Otherwise the three-valued table on remaining children (binary form; n-ary is
the same fold: any `NOT_SATISFIED` wins, else any `UNKNOWN`, else
`SATISFIED`):

| child A \ child B | `SATISFIED` | `NOT_SATISFIED` | `UNKNOWN` |
|---|---|---|---|
| `SATISFIED` | `SATISFIED` | `NOT_SATISFIED` | `UNKNOWN` |
| `NOT_SATISFIED` | `NOT_SATISFIED` | `NOT_SATISFIED` | `NOT_SATISFIED` |
| `UNKNOWN` | `UNKNOWN` | `NOT_SATISFIED` | `UNKNOWN` |

**ANY after discarding `ABSENT` children.** If none remain → `ABSENT`.
Otherwise:

| child A \ child B | `SATISFIED` | `NOT_SATISFIED` | `UNKNOWN` |
|---|---|---|---|
| `SATISFIED` | `SATISFIED` | `SATISFIED` | `SATISFIED` |
| `NOT_SATISFIED` | `SATISFIED` | `NOT_SATISFIED` | `UNKNOWN` |
| `UNKNOWN` | `SATISFIED` | `UNKNOWN` | `UNKNOWN` |

**`AT_LEAST(k_projection)` is not the original `k` after projection.**

`requirement_group_projection_thresholds(group_node_id, projection,
k_projection, n_projected, PK(group_node_id, projection))` is written at
rule-set verification and is immutable afterward.

For each group and each of the five projections, verification computes
`n_projected` = count of structural children whose projected class is not
`ABSENT` under that projection:

- if `n_projected = 0`: no threshold row is stored; evaluation returns
  `ABSENT` and **does not** apply a `k`;
- if `n_projected > 0`: a row **must** exist with
  `1 <= k_projection <= n_projected`. Missing, extra, `k_projection < 1`,
  `k_projection > n_projected`, or a row for a projection with
  `n_projected = 0` → verification **fails closed**. No `k` is inferred by
  subtracting `ABSENT` children from the original `minimum_children`.
- `FULL.k_projection` must equal the rule node’s original `minimum_children`,
  and `FULL.n_projected` must equal the structural child count.
- If a projection retains every structural child (no class becomes `ABSENT`),
  `k_projection` must equal `minimum_children`.
- Ordinary-hard, conditional-hard, and soft projections each have their own
  `k_projection` row when `n_projected > 0`. Mixed ordinary+soft or
  ordinary+conditional `AT_LEAST` groups therefore cannot silently reuse
  original `k`.

Evaluation of `AT_LEAST` after discarding `ABSENT`: let `n` be remaining
children, `s` the count of `SATISFIED`, `u` the count of `UNKNOWN`:

- `n = 0` → `ABSENT`;
- `s >= k_projection` → `SATISFIED`;
- `s + u < k_projection` → `NOT_SATISFIED`;
- otherwise → `UNKNOWN`.

If evaluation would need a `k_projection` and none is stored, finalization
fails closed. Caller projection values are not an input.

SQL writes
`eligibility_requirement_projection_results(evaluation_id,rule_node_id,
projection,value,PK(evaluation_id,rule_node_id,projection))` only during
finalization after recomputing every node.

The outcome function is the following complete ordinary/conditional 4×4
table. Rows are the `ORDINARY_BARRIER` root (ordinary-hard decision
projection) and columns are the `CONDITIONAL_HARD` root.
Derivation, with no implicit cells:

- `ORDINARY_BARRIER = NOT_SATISFIED` → `NOT_ELIGIBLE` regardless of
  conditional (an unavoidable ordinary-hard barrier remains);
- `ORDINARY_BARRIER = UNKNOWN` → `UNKNOWN` regardless of conditional (the
  projected ordinary tree did not resolve the barrier; alternatives are
  already folded into `ALL`/`ANY`/`AT_LEAST`);
- `ORDINARY_BARRIER = SATISFIED` or `ABSENT` → no ordinary barrier; derive
  from `CONDITIONAL_HARD` using the frozen explicit-conditional contract:
  `SATISFIED`/`ABSENT` → `ELIGIBLE`; `NOT_SATISFIED` →
  `CONDITIONALLY_ELIGIBLE`; `UNKNOWN` → `UNKNOWN`.

`INVALID_STATE` is an explicit finalization failure for pairs the projection
definitions cannot produce: a non-`ABSENT` ordinary root means at least one
ordinary-hard descendant exists and remains in `CONDITIONAL_HARD`, so
conditional `ABSENT` is impossible. Independent per-projection `k_projection`
can produce `NOT_SATISFIED`/`UNKNOWN` ordinary with `SATISFIED` conditional;
those cells are therefore real outcomes, not invalid.

Soft projection never causes `NOT_ELIGIBLE` or `UNKNOWN`: soft leaves are
`ABSENT` in both `ORDINARY_BARRIER` and `CONDITIONAL_HARD`. Soft-only trees
are `ABSENT`/`ABSENT` = `ELIGIBLE`.

Frozen explicit-conditional interpretation: a conditional
`NOT_SATISFIED` yields `CONDITIONALLY_ELIGIBLE` only when
`ORDINARY_BARRIER` is `SATISFIED` or `ABSENT`. It never yields
`NOT_ELIGIBLE` by itself.

| `ORDINARY_BARRIER` \ `CONDITIONAL_HARD` | `ABSENT` | `SATISFIED` | `NOT_SATISFIED` | `UNKNOWN` |
|---|---|---|---|---|
| `ABSENT` | `ELIGIBLE` | `ELIGIBLE` | `CONDITIONALLY_ELIGIBLE` | `UNKNOWN` |
| `SATISFIED` | `INVALID_STATE` | `ELIGIBLE` | `CONDITIONALLY_ELIGIBLE` | `UNKNOWN` |
| `NOT_SATISFIED` | `INVALID_STATE` | `NOT_ELIGIBLE` | `NOT_ELIGIBLE` | `NOT_ELIGIBLE` |
| `UNKNOWN` | `INVALID_STATE` | `UNKNOWN` | `UNKNOWN` | `UNKNOWN` |

This covers soft-only (`ABSENT/ABSENT`), conditional-only, ordinary-only,
mixed `ALL`/`ANY`, and mixed explicit-threshold alternatives without implicit
cells. `FULL`, `CONDITIONAL_ONLY`, and `SOFT_EXPLANATION` never own outcome.
SQL also rejects missing, extra, duplicate, disconnected, cyclic,
wrong-rule-set, or caller-mismatched leaf results.

013 version-gates `eligibility_evaluations` outcome checks. v0.1 rows keep
the existing `root_truth_value`/`outcome` constraint and
`input_schema_version = 'eligibility-v0.1'`, and remain finalizable only by
`finalize_eligibility_evaluation(uuid, eligibility_outcome)`. v0.2 rows are
created only by `start_eligibility_evaluation_v02` and finalized only by
`finalize_eligibility_evaluation_v02(uuid)`, which derives projections and
outcome, never trusts a caller outcome, and writes additive
`result_fingerprint`. v0.2 `root_truth_value` is the `FULL` root and does not
determine outcome. No v0.1 row is rewritten. The v0.1 function is not
overloaded or replaced.

## 14. Privacy deletion closure and tombstone

Deletion closure is additive by migration ownership. There is no plugin
framework.

012 installs the stable outer
`delete_student_data(p_student_id uuid, p_reason text)` as the student
executor, with the section 3 search_path and section 6 student lifecycle lock.
The outer function:

1. locks the student lifecycle;
2. inserts one transaction-bound row in
   `private.student_deletion_authorizations(transaction_id, student_id,
   executor_role)`;
3. deletes the `students` parent;
4. calls `private.close_student_owned_rows(p_student_id uuid)`;
5. writes the tombstone;
6. deletes the authorization.

Guards permit cascade deletion only when
`current_user=foundation_student_executor`, the authorization matches
`txid_current()`, and the owning student parent is already absent. Direct child
delete cannot satisfy all three conditions. 013 must not replace, overload, or
change the public signature, owner, callers, search_path, or lock contract of
`delete_student_data`.

`private.close_student_owned_rows(uuid)` is a migration-owner `SECURITY
INVOKER` helper. `EXECUTE` is granted only to `foundation_student_executor`.
012’s body anti-joins **only** 001–011 student-owned tables plus new 012
student-owned foundation rows. It MUST NOT name or reference 013 tables.

**012 closed set (normative after 012):**

- `private.student_identities`, profiles, completeness, student evidence,
  degrees, courses, tests, experiences, skills, joins, goals, preferences,
  student mappings, derived feature values, and
  `private.student_lifecycle_audit`;
- Eligibility v0.1 `eligibility_evaluations`, every 008
  `eligibility_manifest_*` table, `eligibility_requirement_results`,
  `eligibility_course_matches`, and `eligibility_test_matches`;
- Fit intent sets, declarations, validation issues, all typed intent children,
  and `private.fit_student_access_contexts`;
- Fit evaluations, pinned methods, private assembly authorization, every
  manifest subtype, student-field use, financial normalization, input-domain
  state, dimension result, signal/evidence, and reason.

After cascade, the 012 helper performs anti-joins over that 012 list and fails
atomically if any row remains. It does not delete Phase 1 catalog, taxonomy,
non-student Fit registries/context, or aggregate rows that contain no
student/profile/evaluation key and have passed a separate de-identification
contract.

**013 extension mechanism (chosen, narrow):** 013 issues
`CREATE OR REPLACE FUNCTION private.close_student_owned_rows(uuid)` with the
same identity arguments, owner, `SECURITY INVOKER`, and executor-only
`EXECUTE`. The replacement body must retain the complete 012 closed set and
add anti-joins for:

- v0.2 domain snapshots and membership/universe rows;
- negative-authority/scope rows;
- v0.2 replay pins;
- v0.2 projection-result rows and evaluation/result/fingerprint rows that
  cascade from `eligibility_evaluations`.

013 does not add a registry, hook table, or extra public delete function.
012→013 upgrade tests prove the 012 closed set still anti-joins and that the
new 013 tables also close. The shared student lifecycle lock remains the
common serialization primitive.

`student_deletion_tombstones` contains only random `tombstone_id`,
`deleted_at`, a closed non-PII `reason_code`, and free-text-free
`request_class`. It contains no student/auth/profile/evaluation ID, hash,
locator, actor, IP, or document reference. Existing tombstones are preserved.
Because the 005 `deletion_reason` column is `NOT NULL`, 012 renames it
`legacy_deletion_reason`, removes it from all read grants, and writes the fixed
literal `MIGRATED_TO_REASON_CODE` for new tombstones; no caller text enters it.

## 15. Taxonomy ordinal, serialization, and fingerprints

### 15.1 Controlled taxonomy release lifecycle

**Independence decision.** Existing 001–011 taxonomy identity uses
`release_code` text and `introduced_in_release` / `retired_in_release` text
FKs. No 001–011 invariant independently requires numeric ordinals. Ordinals
exist solely so Eligibility v0.2 can prove active-at-pinned-release membership
without lexical comparison. Therefore 012 does not create ordinal columns,
the allocator table, or `introduced_release_ordinal` /
`retired_release_ordinal`.

**012 lifecycle hardening.** 012 adds `status DRAFT|VERIFIED|RETIRED`,
`verified_by`, `verified_at`, `retired_at`, and `retirement_reason` to
`taxonomy_releases`. Existing `v0.1` is backfilled `VERIFIED` without changing
its release code or published time. Direct release DML is revoked.
`create_taxonomy_release(text,timestamptz,text)` inserts `DRAFT` and locks only
the release row. `verify_taxonomy_release(text,text)` performs
`DRAFT → VERIFIED`. `retire_taxonomy_release(text,text)` performs
`VERIFIED → RETIRED`. Release code and publication fields are immutable.
Retirement changes only terminal fields. 012 concept create/retire continues
to use the existing 004 text release FKs.

**013 ordinal semantics.** 013 adds immutable positive unique
`release_ordinal bigint`. Existing `v0.1` is backfilled ordinal 1. Any
additional 012-created releases are backfilled consecutive ordinals by
`created_at`, then `release_code`. 013 creates
`private.taxonomy_release_ordinal_allocator(singleton boolean PK CHECK
(singleton), next_ordinal bigint)` with one row, backfilled
`next_ordinal = max(existing ordinal)+1`.

013 `CREATE OR REPLACE`s `create_taxonomy_release` (same identity arguments,
owner, callers, path) to use this exact sequence:

1. lock the singleton allocator row `FOR UPDATE` (correctness boundary; no
   advisory hash);
2. compute `allocated = GREATEST(next_ordinal,
   (SELECT COALESCE(MAX(release_ordinal), 0) + 1 FROM taxonomy_releases))`;
3. insert the release as `DRAFT` with immutable `release_ordinal = allocated`
   (`allocated >= 1`);
4. set `next_ordinal = allocated + 1`;
5. post-lock revalidation: `allocated` is unique and positive; no other
   committed row has that ordinal; `introduced`/`retired` ranges of existing
   verified content remain valid. Failure raises `55000` and rolls back.

Rollback rolls back both the insert and the allocator increment.
013 `CREATE OR REPLACE`s `verify_taxonomy_release` to keep `DRAFT → VERIFIED`
and additionally reject empty, reversed, or out-of-release ordinal ranges.
Ordinal mutation after insert always fails.

Concurrent create after 013: the winner is the transaction that first holds
the allocator `FOR UPDATE`. It receives `max(ordinal)+1`. The loser blocks,
then allocates the next distinct positive ordinal. Both commit; neither can
insert a duplicate ordinal. A rollback returns that ordinal to the
`GREATEST(next_ordinal, max+1)` computation of the next creator.

Concepts, aliases, relationships, mappings, v0.2 rule verification, and v0.2
evaluation start use ordinal membership
`introduced_release_ordinal <= pin_ordinal AND (retired_release_ordinal IS
NULL OR pin_ordinal < retired_release_ordinal)`. When `retired` is not null,
the range is non-empty, so `introduced_release_ordinal <
retired_release_ordinal` (half-open interval). Empty, reversed, or equal
introduced/retired ranges fail verification. Draft/retired releases cannot
start rules or evaluations. Lexical release comparison and hash-only ordinal
correctness are forbidden.

013 adds non-null `introduced_release_ordinal` and nullable
`retired_release_ordinal` to concepts, aliases, and relationships; v0.1 content
is backfilled introduced ordinal 1 and null retired ordinal. 013
`CREATE OR REPLACE`s the 012 taxonomy create/retire functions so creation
requires the introducing release to be `DRAFT` and writes the ordinal columns.
A semantic retirement function requires the named retirement release to be a
later `DRAFT` release, locks release then semantic row, and sets only
`retired_release_ordinal`; that retirement becomes effective only when the
release verifies. Mapping and rule pins copy the applicable ordinals.

### 15.2 Canonical scalar and container rules

`eligibility-v0.2-c14n1` canonicalization is regenerated from normalized pin
rows. Production **does not persist** the canonical bytes or canonical JSON
(no `bytea`, no document `jsonb`, no text payload column). Production persists
normalized replay rows plus SHA-256 fingerprints only. Golden byte vectors live
only in
`packages/eligibility-engine/contracts/vectors/` (test corpus, not student
data).

Scalar rules (closed):

- boolean = JSON literals `true` / `false` only; never `0`/`1`/`"true"`;
- SQL NULL and JSON absence are distinct: a required key is never missing;
  a nullable required key is present as JSON `null`;
- UUID = lowercase canonical 36-character `8-4-4-4-12` text;
- timestamp = UTC `YYYY-MM-DDTHH:MM:SS.ffffffZ` (microsecond precision,
  trailing zeros retained to six fractional digits); dates = `YYYY-MM-DD`;
- decimal = minimal non-exponent base-10 lexical form, trailing fractional
  zeros removed, `-0` becomes `0`; NaN/infinities forbidden;
- integer = base-10 without sign padding;
- enum = exact uppercase PostgreSQL/registry label (`SATISFIED`,
  `ORDINARY_BARRIER`, `VERIFIED`, …); never mixed case or alias;
- text = UTF-8, Unicode NFC, then RFC 8259 escaping; no BOM; control
  characters use lowercase `\u00xx`; invalid Unicode fails;
- object keys sorted by Unicode scalar value; duplicate object keys
  forbidden; unknown keys forbidden.

The only opaque JSON scalars are existing `canonicalValue` and student
evidence `metadata`. Within those values, objects use the object/scalar rules
above and arrays preserve stored order with duplicates significant; they are
not schema collections and are never re-sorted.

In the schemas below, every key ending `Id` is UUID or explicit null where
shown nullable; every `*Hash` is 64 lowercase hex; `ruleSetVersion`,
`releaseOrdinal`, introduced/retired ordinals, `sortOrder`, and
`minimumChildren` are integers; scores, credits, GPA,
confidence, and grade numbers are decimals under the rule above; code/status/
kind/method/relation/operator/strength/semantics/domain/scope/projection fields
are exact closed registry labels; and all other scalar fields are NFC text,
timestamp, date, boolean, or null as named. No scalar coercion from text is
permitted.

### 15.3 Exact decision-input logical object

The root has exactly these keys and nested shapes:

```text
{
  contract: {releaseCode, inputSchemaVersion, resultSemanticsVersion,
             canonicalizationVersion},
  profile: {profileVersionId, studentId, snapshotHash},
  evaluator: {name, version, buildHash},
  ruleSet: {ruleSetId, programVersionId, ruleSetVersion, ruleSchemaVersion,
            engineContractVersion, verificationEvidenceId, verifiedBy,
            verifiedAt},
  taxonomy: {releaseCode, releaseOrdinal},
  ruleNodes: [{ruleNodeId,parentNodeId,sortOrder,nodeKind,groupOperator,
               minimumChildren,predicateKind,requirementStrength,
               requirementSemantics,targetConceptId,explanationTemplate}],
  projectionThresholds: [{groupNodeId,projection,kProjection,nProjected}],
  ruleNodeSources: [{ruleNodeId,fieldObservationId,sourceId,
                     applicabilityAssertionId,
                     applicabilityHeadAssertionIdAtPin,
                     applicabilityScopeId,knowledgeStatusAtPin}],
  catalogSelections: [{recordType,recordId,fieldName,observationId,
                       selectedAtPin,selectedByPin}],
  catalogObservations: [{fieldObservationId,sourceId,sourceIdentityId,
                         sourceRevisionNumber,retrievalContentHash,
                         evidenceId,recordType,recordId,fieldName,
                         canonicalValue,knowledgeStatus,programScopeKey,
                         programVersionScopeKey,granularityScope,
                         populationScopeCode,cycleScopeCode}],
  catalogMappings: [{catalogMappingId,recordType,recordId,conceptId,
                     relationAtPin,method,confidence,modelVersion,
                     verificationEvidenceId,reviewedBy,reviewedAt,
                     statusAtPin}],
  taxonomyConcepts: [{conceptId,canonicalKey,conceptKind,
                      introducedReleaseOrdinal,retiredReleaseOrdinal}],
  completenessScopes: [{scopeId,scopeKind,educationContextId,domain,
                        completenessId,completeness,explanation}],
  degrees: [{scopeId,studentDegreeId}],
  courses: [{scopeId,studentCourseId}],
  testScores: [{scopeId,studentTestScoreId}],
  studentMappings: [{scopeId,studentMappingId,universeRole,recordType,
                     studentRecordId,conceptId,relationAtPin,method,confidence,
                     modelVersion,studentEvidenceId,reviewedBy,reviewedAt,
                     statusAtPin}],
  studentEvidence: [{studentEvidenceId,evidenceType,locator,contentHash,
                     observedAt,metadata}],
  degreeFacts: [{studentDegreeId,institutionName,degreeName,degreeLevel,
                 degreeStatus,startDate,completionDate,countryCode,gpaValue,
                 gpaScale,studentEvidenceId}],
  courseFacts: [{studentCourseId,studentDegreeId,courseCode,courseTitle,
                 courseStatus,term,completionDate,credits,gradeValue,
                 gradeScale,gradeText,studentEvidenceId}],
  testFacts: [{studentTestScoreId,assessmentConceptId,testDate,totalScore,
               sectionScores:{sectionCode:decimal},studentEvidenceId}]
}
```

Negative-authorization rows are **result artifacts**, not decision inputs.
The input already contains the completeness, membership, and mapping universes
the finalizer uses to construct them. Including them in the input hash would
mix derived proof with inputs.

Every collection below is a set: order is not meaningful, duplicates are
illegal, and missing required keys fail canonicalization.

| Collection | Sort key | Duplicate identity | Order meaningful? | Duplicates illegal? |
|---|---|---|---|---|
| `ruleNodes` | `ruleNodeId` | `ruleNodeId` | no | yes |
| `projectionThresholds` | `(groupNodeId,projection)` | `(groupNodeId,projection)` | no | yes |
| `ruleNodeSources` | `(ruleNodeId,fieldObservationId)` | `(ruleNodeId,fieldObservationId)` | no | yes |
| `catalogSelections` | `(recordType,recordId,fieldName)` | `(recordType,recordId,fieldName)` | no | yes |
| `catalogObservations` | `fieldObservationId` | `fieldObservationId` | no | yes |
| `catalogMappings` | `catalogMappingId` | `catalogMappingId` | no | yes |
| `taxonomyConcepts` | `conceptId` | `conceptId` | no | yes |
| `completenessScopes` | `(scopeKind,educationContextId null-first,domain,scopeId)` | `scopeId` and `(scopeKind,educationContextId,domain)` | no | yes |
| `degrees` | `(scopeId,studentDegreeId)` | `(scopeId,studentDegreeId)` | no | yes |
| `courses` | `(scopeId,studentCourseId)` | `(scopeId,studentCourseId)` | no | yes |
| `testScores` | `(scopeId,studentTestScoreId)` | `(scopeId,studentTestScoreId)` | no | yes |
| `studentMappings` | `(scopeId,universeRole,studentMappingId)` | `(scopeId,studentMappingId)` | no | yes |
| `studentEvidence` | `studentEvidenceId` | `studentEvidenceId` | no | yes |
| `degreeFacts` | `studentDegreeId` | `studentDegreeId` | no | yes |
| `courseFacts` | `studentCourseId` | `studentCourseId` | no | yes |
| `testFacts` | `studentTestScoreId` | `studentTestScoreId` | no | yes |
| `sectionScores` keys | Unicode scalar value of `sectionCode` | `sectionCode` | no | yes |

`educationContextId` null-first uses JSON `null` before any UUID. No database
insertion order is observable. Each `sectionScores` key is a nonempty NFC
section code matching `^[A-Z0-9][A-Z0-9._:-]{0,63}$`; values are non-null
decimals. Opaque `canonicalValue` / `metadata` arrays are the sole exception:
stored order is preserved and duplicates are significant; they are not schema
collections.

### 15.4 Exact result logical object

The result root has exactly:

```text
{
  contract: {resultSemanticsVersion, canonicalizationVersion},
  decisionInputFingerprint,
  roots: {full,ordinaryBarrier,conditionalHard,conditionalOnly,softExplanation},
  outcome,
  nodeResults: [{requirementResultId,ruleNodeId,truthValue,reasonCodes,
                 explanation,
                 supportingFactRefs:[{type,id}],
                 missingData:[{code,scopeId,field}],
                 decisive}],
  projectionResults: [{ruleNodeId,projection,value}],
  courseMatches: [{courseMatchId,ruleNodeId,catalogMappingId,
                   studentMappingId,studentCourseId,studentEvidenceId}],
  testMatches: [{testMatchId,ruleNodeId,studentTestScoreId,
                 studentEvidenceId}],
  negativeAuthorizations: [{ruleNodeId,domain,proofVersion,scopeIds}]
}
```

Sort keys, duplicate identity, and duplicate policy for result collections:

| Collection | Sort key | Duplicate identity | Order meaningful? | Duplicates illegal? |
|---|---|---|---|---|
| `nodeResults` | `ruleNodeId` | `ruleNodeId` | no | yes |
| `reasonCodes` | Unicode scalar value | code string | no | yes |
| `supportingFactRefs` | `(type,id)` | `(type,id)` | no | yes |
| `missingData` | `(code,scopeId null-first,field)` | `(code,scopeId,field)` | no | yes |
| `projectionResults` | `(ruleNodeId,projection)` | `(ruleNodeId,projection)` | no | yes |
| `courseMatches` | `(ruleNodeId,studentCourseId,catalogMappingId,studentMappingId)` | that tuple | no | yes |
| `testMatches` | `(ruleNodeId,studentTestScoreId)` | that pair | no | yes |
| `negativeAuthorizations` | `ruleNodeId` | `ruleNodeId` | no | yes |
| `scopeIds` | ascending UUID | UUID | no | yes |

`supportingFactRefs.type` is exactly `DEGREE`, `COURSE`, `TEST_SCORE`,
`STUDENT_MAPPING`, `CATALOG_MAPPING`, or `FIELD_OBSERVATION`.
`missingData.code` is a closed registry value. Roots use the four-state union
except `full`, which cannot be `ABSENT`. Negative-authorization rows live
only here, never in the input object.

`input_fingerprint` and `result_fingerprint` on v0.2 evaluations are lowercase
SHA-256 hex over the respective regenerated canonical UTF-8 bytes. These
structures and helpers are 013-owned. Production persists normalized pin rows
and hashes only—**not canonical bytes or canonical JSON**.
`finalize_eligibility_evaluation_v02` regenerates input twice (before seal and
before completion), compares hashes, regenerates the result, and stores its
hash. Replay regenerates from normalized pins and fails on mismatch. Canonical
byte vectors exist only in
`packages/eligibility-engine/contracts/vectors/`. Effective roots are result
fields and never enter the input hash. Existing 008 `input_fingerprint` values
on v0.1 rows are unchanged and are not recomputed by 013.

## 16. Mechanical SQL/TypeScript parity

013 creates one versioned registry source file for generation,
`packages/eligibility-engine/contracts/eligibility-v0.2.json`, containing the
knowledge states, truth states, outcomes, projection names, operators,
canonical field order, array sort keys, reason codes, and contract versions.
It is data, not a policy DSL.

A deterministic generator emits:

- SQL seed/check fragments consumed by 013 tests;
- TypeScript `as const` registries and unions;
- one shared JSON Lines corpus containing all knowledge states; exhaustive
  `ALL`, `ANY`, and `AT_LEAST` truth rows; soft-only, conditional-only, mixed
  alternatives, and mixed-threshold trees; absence snapshots; canonical bytes;
  input hashes; roots; outcomes; and result hashes.

CI runs the generator with `--check` and fails on any diff. SQL and TypeScript
both execute the same corpus and compare exact canonical-byte hex, hashes,
node projections, and outcomes. TypeScript exhaustive switches use `never`;
SQL checks registry set equality in both directions. No hand-maintained enum or
reason-code list is accepted.

The exact knowledge-state set is `KNOWN`, `UNKNOWN`,
`NOT_PUBLICLY_DISCLOSED`, `NOT_YET_RESEARCHED`, `NOT_YET_VERIFIED`,
`NOT_APPLICABLE`, `SOURCE_CONFLICT`, and `STALE`. Every non-`KNOWN` value maps
to Eligibility `UNKNOWN`; `NOT_APPLICABLE` is not a fourth truth value.

## 17. Twelve-row finding ledger

This ledger contains exactly the twelve confirmed findings. It has six
`CRITICAL`, four `HIGH`, and two `MEDIUM` rows.

| Finding | Severity | Phase | Affected objects | Root cause | Migration owner | Exact invariant after fix | Positive test | Negative/adversarial test | Replay/history test | Concurrency test if applicable | Status |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Unscoped Phase 1 evidence | CRITICAL | Phase 1 foundation | `sources`, `evidence_items`, `field_observations`, `canonical_field_selections`, ten catalog tables | Evidence has no normalized exact record/field/cycle/population applicability authority. | 012 | Every prospective `KNOWN` observation and selection has one headed `REVIEWED_APPLICABLE` assertion exactly matching evidence, record type/ID, field, and relevant scope. | Select a correctly scoped reviewed observation and verify canonical value/head. | Offer institution, school, other-program, wrong-field, wrong-cycle, wrong-population, reviewed-inapplicable, and legacy-unasserted evidence; each fails with the scoped guard identity. | Pre-012 selections remain unchanged and linked only to `LEGACY_UNASSERTED`; no scope is inferred. | Two reviewers of one scope serialize; one head wins and the loser revalidates after blocking. | CONFIRMED — FIXED BY 012 |
| Mutable provenance | CRITICAL | Phase 1 foundation | `source_identities`, `sources`, `evidence_items` | `sources` is mutable and `UNIQUE(url)` conflates logical identity with retrieval revision. | 012 | Source rows are immutable revisions; same-identity revisions are consecutive, supersede one prior revision, and may reuse a URL without changing old evidence FKs. | Create revision 2 for the same identity/URL and verify revision lineage and old evidence pointer. | Update/delete publisher, title, URL, tier, type, revision metadata, timestamps, or cross-identity supersession; each fails. | Revision-1 rows and all existing evidence references remain byte-for-byte unchanged. | Concurrent next-revision creation locks the identity; exactly one revision number commits. | CONFIRMED — FIXED BY 012 |
| Spoofable controlled-write GUC authorization | CRITICAL | Phases 1–3 security | All lifecycle tables/functions guarded by the ten production `app.*` flags in 002 and 005–011 | Caller-settable custom GUC values are treated as authorization. | 012 | Lifecycle authority requires exact `current_user` executor identity through a fixed-path 9A entry point; no GUC, JWT text, RLS bypass, or session residue authorizes DML. | Each approved 9A entry point completes one legal transition under its executor. | As hosted-style `service_role BYPASSRLS`, set every flag locally and session-wide and attempt every direct transition/delete; all fail. | Existing terminal rows remain unchanged and readable; removed flags do not alter their meaning. | Same-object 9A entry points obey the section 6 lock protocol; spoofing cannot bypass a blocked transition. | CONFIRMED — FIXED BY 012 |
| Verified rule/mapping replay mutation | CRITICAL | Phase 2 replay foundation | `program_requirement_rule_sets`, nodes/sources/mappings, `catalog_concept_mappings`, Fit context mappings, existing 008 evaluation/manifest/result rows | Guards constrain status transitions but do not make every verified semantic and review field immutable during retirement/reuse. | 012 | Verified payload on existing 001–011 objects is immutable; retirement changes only status/time/reason; rejected/retired rows are fully immutable; current-start authority is separate from historical readability. v0.2 at-use pin tables are 013 (see 9B/12.1). | Retire a verified object through its 9A entry point and verify only the three retirement fields change. | Mutate rule header/content, mapping record/concept/relation/method/evidence/reviewer/supersession, or a completed 008 evaluation/manifest/result; each fails. | Completed v0.1 evaluations retain original 008 identities/results; a new start rejects a retired object. | Retirement versus v0.1 evaluation start/finalize serializes on sorted object locks. | CONFIRMED — FIXED BY 012 |
| Fabricated negative eligibility | CRITICAL | Phase 2 Eligibility | Student completeness/data tables, Eligibility domain snapshots/manifests, requirement results and negative authorizations | Caller result/reason text can claim absence without closed authoritative domain coverage. | 013 | Course, test, or degree `NOT_SATISFIED` exists only when SQL reconstructs complete normalized scopes, exact set equality, and no satisfying or unresolved mapping/fact; otherwise truth is `UNKNOWN`. | Finalize complete empty course, test, and degree domains and persist SQL-created negative authorizations. | Omit/add a row/context, use partial/unknown/missing completeness, hide a satisfying fact, leave a proposal, or fabricate a reason; each is rejected or recomputed `UNKNOWN`. | v0.1 negatives/results are untouched; v0.2 proof rows reproduce from immutable snapshots. | Seal/finalize versus profile deletion serializes on student/evaluation locks; sealed sets cannot race with mutation. | CONFIRMED — FIXED BY 013 |
| Incomplete recursive eligibility truth validation | CRITICAL | Phase 2 Eligibility | `program_requirement_nodes`, `eligibility_requirement_results`, `eligibility_evaluations`, projection thresholds | 008 checks result count/root presence but trusts caller internal-node truth and outcome and does not recursively validate all operators/projections. | 013 | SQL recomputes every node bottom-up for `ALL`, `ANY`, and explicit-threshold `AT_LEAST`, all five projections, and the derived outcome; missing/extra/duplicate/disconnected/cyclic/cross-rule results fail. | Exhaustive truth tables plus five-level valid trees finalize with derived roots/outcome. | Lie at each leaf/group/root; vary invalid `k`, cycles, disconnected nodes, duplicates, omissions, extras, and wrong-rule nodes; each fails. | Completed v0.1 roots/outcomes remain byte-for-byte unchanged; v0.2 stores separate projection results. | Concurrent result assembly/sealing/finalization on one evaluation serializes and accepts one sealed tree only. | CONFIRMED — FIXED BY 013 |
| SQL/TypeScript eligibility semantic contradiction | HIGH | Phase 2 Eligibility | SQL finalizer, TypeScript evaluator/types/reasons, root/outcome constraints | SQL v0.1 ties outcome to literal root while application semantics require ordinary-hard, conditional-hard, and soft ownership, including mixed alternatives. | 013 | SQL and TypeScript implement the section 13 five-projection algorithm exactly; soft-only, conditional-only, mixed alternatives, and explicit projected `AT_LEAST` thresholds derive the same outcome. | Shared corpus covers soft-only, conditional-only, mixed `ALL`/`ANY`, ordinary plus conditional, and mixed-threshold cases with equal outputs. | Feed unsupported conditional-soft shape, absent projected threshold, caller outcome/root mismatch, and permutation variants; both layers reject identically. | v0.1 result semantics and rows are not relabeled; v0.2 uses new contract/result markers. | N/A — pure evaluation parity; persistence concurrency is covered by the recursive-validation row. | CONFIRMED — FIXED BY 013 |
| Missing SQL/TypeScript knowledge-state parity | HIGH | Phase 2 Eligibility | SQL `knowledge_status`, TypeScript `KnowledgeStatus`, adapters/serializers | SQL has eight states while TypeScript and hand-maintained adapters can omit or reinterpret states. | 013 | Generated SQL and TypeScript registries have identical closed sets; every non-`KNOWN` state maps to Eligibility `UNKNOWN`, and `NOT_APPLICABLE` is not a truth value. | Run one shared-corpus case for each of the eight states and exact DTO round trip. | Generator `--check`, SQL set equality, and TypeScript exhaustive `never` fail after adding/removing/renaming one side only. | Existing stored knowledge states preserve spelling and meaning; no backfill rewrites them. | N/A — immutable registry/build check. | CONFIRMED — FIXED BY 013 |
| Taxonomy release pin not enforced | HIGH | Phase 2 taxonomy/replay | `taxonomy_releases`, concepts, aliases, relationships, catalog mappings, rule sets, evaluation manifests | Release codes are text and current-active checks do not prove membership at the pinned release. | 013 | Immutable positive unique ordinal defines `introduced <= pin < retired` for every pinned taxonomy object; lexical release comparison is forbidden. | Verify and evaluate a concept/alias/relation active at the pinned ordinal. | Use a later-introduced, already-retired-at-pin, out-of-release mapping, extra manifest concept, and lexical traps `v0.9`, `v0.10`, `v10.0`; each fails. | Existing `v0.1` pins remain ordinal 1; completed evaluations and fingerprints are unchanged. | Concurrent release creation holds the single ordinal lock and assigns distinct consecutive ordinals. | CONFIRMED — FIXED BY 013 |
| Active program may have zero `PRIMARY_ADMINISTRATIVE` school | HIGH | Phase 1 catalog | `programs`, `program_schools`, `program_schools_one_primary` | Existing partial unique index enforces at most one primary but not at least one. | 012 | Every non-retired `COMPLETE` program has exactly one active same-university primary; only `COMPLETE` may be `ACTIVE`; no exception row exists. | Complete a draft with one primary and atomically replace that primary in one transaction. | Commit complete/active with zero or two primaries, retire sole primary, use joint-only or cross-university primary; each fails. | Existing valid MSQE becomes additively `COMPLETE`; historical catalog columns and retired rows are unchanged. | Two-session replacement/retirement on one program serializes and cannot commit zero/two primaries. | CONFIRMED — FIXED BY 012 |
| Mutable/deletable `program_derived_features` | MEDIUM | Phase 1 derived data | `program_derived_features`, `student_feature_definitions`, `student_derived_feature_values` | Program-derived rows lack append-only guards and definition history is not closed after use. | 012 | Program/student values are append-only with same-feature supersession; referenced definitions are semantically immutable and retire only through the entry point; privacy deletion is the sole student-value delete. | Append a replacement program feature with valid same-program/name supersession and create a new definition version/value. | Update/delete a program feature, cross-feature supersede, mutate a referenced definition, or directly delete a student value; each fails. | Existing derived rows remain unchanged and excluded from Eligibility inputs; supersession preserves prior versions. | Concurrent supersession of one head serializes; only one successor can claim the prior row. | CONFIRMED — FIXED BY 012 |
| False-positive negative tests | MEDIUM | Phases 1–3 verification | SQL tests 001–003 and new 012/013 suites | Broad `WHEN OTHERS` and fixtures with unrelated restrictive FKs can pass without exercising the intended guard. | 012 | Every expected failure asserts SQLSTATE plus exact constraint/function/stable-message identity on an otherwise valid isolated fixture; disabling the intended guard makes the test fail. | Prove each attack fixture succeeds when the single intended guard is deliberately absent in an isolated rollback harness. | Trigger the guarded operation and assert exact failure identity; inject an unrelated FK failure and prove it does not satisfy the test. | Before/after historical row counts, IDs, payloads, results, and fingerprints are asserted independently of negative tests. | Two-session cases assert block/unblock and terminal error identity, not merely “some error.” | CONFIRMED — FIXED BY 012 |

### 17.1 Cross-cutting controls outside the confirmed-finding count

Closed initial states, 012 privacy deletion closure over 001–011 plus 012
foundation rows, 013 additive privacy extension, deterministic lock ordering,
trusted-schema `CREATE` revocation, and overload/shadow detection are required
012/013 cross-cutting controls as partitioned in sections 9A/9B and 14.
Canonical serialization and SQL/TypeScript corpus generation remain 013
controls. They do not add, merge, replace, or renumber any of the twelve
confirmed findings above.

### 17.2 Final blocker-closure traceability

These are closure checks, not additional findings. `RESOLVED` means the cited
section contains a concrete schema/function/lock rule and the stated
acceptance proof; absence of either would require `OPEN`.

| # | Blocker-closure contract | Executable contract location | Required proof | Status |
|---:|---|---|---|---|
| 1 | Feasible executor ownership choreography | 3.1 | Hosted install proves preflight, temporary schema privilege, exact-signature owner transfer, revocation, grants, and post-install catalog assertions. | RESOLVED |
| 2 | One student-wide first lock | 6 and 9A; 9B additive | Every 9A profile, mapping, intent, v0.1 evaluation, Fit evaluation, and delete entry point blocks on one `student_id` before any other lock. 013 snapshot/pin/v0.2 finalize callers use the same helper without changing identity or 012 family order. | RESOLVED |
| 3 | Advisory locks not a correctness boundary | 6 | Collision and advisory-disabled tests still preserve invariants through row locks, constraints, and revalidation. | RESOLVED |
| 4 | Direct source parent locking | 6 and 8 | Two successor sessions serialize on `source_identities FOR UPDATE`. | RESOLVED |
| 5 | Full evidence semantic/head key and null treatment | 7 | Equality attacks vary evidence, record type/ID, resolved program, program version, field, granularity, population, and cycle; canonical non-null keys prevent duplicate null scopes. | RESOLVED |
| 6 | Exactly one source current head, current-only successor, acyclic chain | 8 | Fork, stale-head, skipped revision, cross-identity, cycle, and unreachable-head tests fail. | RESOLVED |
| 7 | Complete 012 controlled lifecycle inventory | 9A | After 012, function registry, table grants, direct-DML attacks, lock identity, and audit destination equal section 9A in both directions. 9B is not an 012 proof. | RESOLVED |
| 8 | Exact normalized Eligibility v0.2 replay pins | 12.1 and 9B | Mutate/retire each source semantic after v0.2 start; replay uses pins while a new start applies current authority. 012 must not require these tables. | RESOLVED |
| 9 | First-class global, education, and unassigned scopes | 12.2 | Null-context duplicates, omitted unassigned scope, and cross-context members fail. 013-only. | RESOLVED |
| 10 | Authoritative versus limiting universes and bidirectional equality | 12.3 | Omit/add/swap verified and proposed mappings in each direction; v0.2 finalization rejects each difference. 013-only. | RESOLVED |
| 11 | Four-state projections and executable absence operators | 13 | Shared corpus exhausts `ALL`, `ANY`, and `AT_LEAST` with `ABSENT` at leaf, nested, and root positions. 013-only. | RESOLVED |
| 12 | Complete frozen 4×4 outcome interpretation | 13 | All 16 root pairs produce the named outcome or exact `INVALID_STATE`; explicit-conditional mixed cases match SQL and TypeScript. Executed only by `finalize_eligibility_evaluation_v02`. | RESOLVED |
| 13 | Taxonomy lifecycle vs ordinal lock | 9A, 9B, and 15.1 | 012 proves illegal taxonomy status transitions and direct DML denial without ordinals. 013 proves concurrent ordinal allocate, ordinal mutation denial, lexical traps, and membership-at-pin. | RESOLVED |
| 14 | Exact nested canonical schemas and no persisted production bytes | 15.2–15.4 | Permutation/duplicate/scalar vectors agree byte-for-byte in 013 tests; production has normalized rows plus hashes and no canonical-byte column. | RESOLVED |
| 15 | Preserved migration boundary, ledger, and history | 1, 2, 9A/9B, 17, and 19 | 012/013 ownership, 014 deferral, exact 12-row ledger counts, 012 gates free of 013 objects, and byte-for-byte v0.1/history comparisons pass. | RESOLVED |

### 17.3 Final boundary-conflict table

Each exact invariant/test has one migration owner. Foundation primitives stay
012; Eligibility v0.2 semantics stay 013.

| Boundary item | 012 responsibility | 013 responsibility | Compatibility contract |
|---|---|---|---|
| Eligibility finalizer | Harden `finalize_eligibility_evaluation(uuid, eligibility_outcome)` auth/DML/concurrency/immutability/security without changing the 008 semantic contract | Add `finalize_eligibility_evaluation_v02(uuid)` that derives projections/outcome, never trusts caller outcome, and operates only on v0.2 evaluations | Do not overload or replace the v0.1 signature; v0.1 rows remain replayable under the v0.1 contract |
| Taxonomy lifecycle vs ordinals | Status/create/verify/retire entry points and direct-DML denial on existing release rows; no ordinal columns | Ordinal allocator, `release_ordinal`, introduced/retired ordinals, active-at-release, v0.2 rule verification against the pin | 013 `CREATE OR REPLACE`s the 012 taxonomy signatures, preserving owner/callers/path; 012 tests do not require ordinals |
| Privacy deletion | Stable outer `delete_student_data(...)` plus `private.close_student_owned_rows(uuid)` over 001–011 and 012 student-owned rows | `CREATE OR REPLACE` the helper to add v0.2 snapshots, pins, negative-authority, projection, and fingerprint rows | Public signature, executor owner, search_path, and student lock remain 012; no plugin framework |
| Replay pins | Immutable existing verified objects and 008 evaluation/manifest/result rows; no v0.2 pin tables | Normalized Eligibility v0.2 pin tables and pin-at-use copies | 013 pins reference immutable 012 revision/assertion/observation rows and must not read current heads |
| Fingerprints | Leave existing 008 `input_fingerprint` values unchanged | v0.2 decision/result fingerprint helpers and additive `result_fingerprint` | 012 must not create v0.2 fingerprint schema; 013 must not recompute v0.1 hashes |
| Section 9 controlled entry points | Complete 9A inventory is the 012 acceptance set | Complete 9B inventory; may replace only the named 012 signatures listed in 9B | No 9B row is a 012 acceptance requirement; 013 must not redesign 9A owners, callers, search_path, or lock identity |

## 18. Exact implementation and acceptance gates

**012 is accepted only if all are true.** These checks cover 012-owned objects
only. 012 acceptance MUST NOT require 013 pin tables, 013 projection
semantics, 013 taxonomy ordinals, 013 fingerprint structures, or the v0.2
finalizer.

- clean 001–012 rebuild;
- populated 001–011 → 012 upgrade;
- historical v0.1 Eligibility and Phase 3 IDs and semantic payloads unchanged;
- role/owner/grant/`search_path`/overload assertions for 9A-controlled
  functions, including every `has_schema_privilege(...,'CREATE')` denial and
  function/operator/relation shadow attempt;
- all twelve GUC cases in section 5 are tested and production has zero
  security-dependent `app.*` reads;
- manual GUC bypass attacks are ineffective;
- direct lifecycle DML is rejected on 012-hardened existing objects;
- terminal-state direct inserts are rejected on 012-hardened existing objects;
- every section 9A inventory row equals function/privilege/audit registries in
  both directions;
- two-session concurrency tests for 012 invariants, including the
  one-first-student-lock and advisory-collision cases in section 6;
- evidence applicability tests;
- source revision tests;
- existing-object replay immutability tests (verified/retired 001–011 objects
  and completed 008/011 rows);
- primary-school invariant;
- privacy deletion closure through 001–012 using the section 14 012 closed
  set, with no reference to 013 tables;
- derived-feature treatment and 012 test repairs;
- existing Phase 1/2/3 regression suites remain passing or are explicitly
  updated only where security behavior changed additively;
- all positive, negative/adversarial, replay/history, and applicable
  concurrency cells for the seven 012-owned ledger rows pass;
- real hosted Supabase verifies `authenticated`, `service_role BYPASSRLS`,
  internal roles, and `PUBLIC`.

**013 is accepted only if all are true:**

- clean 001–013 rebuild;
- populated 012 → 013 upgrade;
- every 012 gate remains green;
- historical v0.1 Eligibility unchanged;
- v0.2 domain snapshots;
- closed-world equality;
- omission/extra-row attacks;
- exact mapping universe;
- replay pins;
- `ABSENT` propagation;
- explicit projection thresholds;
- ordinary/conditional outcome table;
- taxonomy ordinal/release validity, including lexical traps `v0.9`, `v0.10`,
  and `v10.0`;
- canonical input/result fingerprints;
- SQL/TypeScript parity corpus;
- `finalize_eligibility_evaluation_v02` derives outcome and never trusts
  caller outcome;
- 013 privacy deletion extension via `CREATE OR REPLACE` of
  `private.close_student_owned_rows(uuid)`;
- no 012 primitive redesign of executor-role, direct-DML, `search_path`,
  student lock identity/order, source revision, evidence applicability, or
  source/current-head locking;
- generator `--check`, strict TypeScript, SQL registry equality, shared
  corpus, regenerated canonical bytes, and both v0.2 fingerprints agree;
  production schema inspection proves no canonical JSON/byte column exists;
- all positive, negative/adversarial, replay/history, and applicable
  concurrency cells for the five 013-owned ledger rows pass;
- renewed contract review approves `foundation-integrity-v1`,
  `phase2-v0.2`, `eligibility-v0.2`, and
  `eligibility-v0.2-c14n1`.

Failure of any item blocks acceptance; there is no “follow-up validation”
placeholder. Across 012 and 013, acceptance accounts for exactly all twelve
confirmed ledger rows: six `CRITICAL`, four `HIGH`, and two `MEDIUM`. 012
proofs cover 9A and 012-owned ledger/blocker rows. 013 proofs cover 9B and
013-owned ledger/blocker rows. All fifteen section 17.2 blocker-closure rows
must retain executable proof for their owning migration before they may remain
`RESOLVED`.

## 19. 014 dependency note and final disposition

014 is not designed or implemented here. It may begin only after 012 and 013
are accepted. It must version the Fit Financial contract so Phase 1
`billing_basis` values (`TOTAL_PROGRAM`, `PER_YEAR`, `PER_SEMESTER`,
`PER_CREDIT`, `UNKNOWN`) are not all treated as
`ACADEMIC_YEAR/GROSS`; preserve scope, period, components, currency, basis, and
quantity assumptions; fail closed to Financial `UNKNOWN`; and create new Fit
contract/method/build/fingerprint versions. It must not alter completed Fit
v0.1 evaluations.

No material 012/013 ownership choice remains open. Migration names, 012
scope A–I, 9A/9B inventories, v0.1 vs v0.2 finalizers, taxonomy
lifecycle/ordinal split, privacy helper extension, locks, 014 deferral, the
12-row ledger, and acceptance gates are fixed by this plan. 013 remains
additive on frozen 012 primitives.

Migration 012 is **FROZEN** as Foundation Hardening / Gate 1. See
[`PHASE_1_2_FOUNDATION_HARDENING_FREEZE.md`](PHASE_1_2_FOUNDATION_HARDENING_FREEZE.md).
012 semantics cannot be patched in place; further changes require a new
additive migration. 013 must not redesign 012 primitives.

MIGRATION 012 FROZEN — READY FOR 013 ELIGIBILITY V0.2
