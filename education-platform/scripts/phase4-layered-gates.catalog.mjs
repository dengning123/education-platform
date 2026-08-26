export const MANIFEST_SCHEMA_VERSION = "PHASE4_LAYERED_GATE_MANIFEST_V1";
export const LIGHT_MIN_FREE_BYTES = 1024 ** 3;
export const HEAVY_MIN_FREE_BYTES = 8 * 1024 ** 3;
export const FROZEN_FIT_RUNTIME_SHA256 =
  "2cad2a2f2ea1d01b6bc1863cbbda6350e84043c865e85f266e01d0512c8dcc9f";

function deepFreeze(value) {
  if (value !== null && typeof value === "object" && !Object.isFrozen(value)) {
    for (const child of Object.values(value)) deepFreeze(child);
    Object.freeze(value);
  }
  return value;
}

export const MIGRATIONS_001_024 = Object.freeze([
  "supabase/migrations/202608200001_core_schema.sql",
  "supabase/migrations/202608200002_provenance_and_audit.sql",
  "supabase/migrations/202608200003_nyu_msqe_golden_record.sql",
  "supabase/migrations/202608200004_taxonomy_v01.sql",
  "supabase/migrations/202608200005_student_profiles.sql",
  "supabase/migrations/202608200006_student_derived_features.sql",
  "supabase/migrations/202608200007_requirement_rules.sql",
  "supabase/migrations/202608200008_eligibility_persistence.sql",
  "supabase/migrations/202608200009_fit_contract_registry.sql",
  "supabase/migrations/202608200010_fit_intents_and_context.sql",
  "supabase/migrations/202608200011_fit_evaluation_persistence.sql",
  "supabase/migrations/202608200012_frozen_foundation_critical_hardening.sql",
  "supabase/migrations/202608200013_eligibility_correctness_v02.sql",
  "supabase/migrations/202608200014_financial_billing_basis_hardening.sql",
  "supabase/migrations/202608200015_fit_replay_and_seal_hardening.sql",
  "supabase/migrations/202608220016_fit_engine_v01_production_registration.sql",
  "supabase/migrations/202608220017_fit_financial_normalization_workflow.sql",
  "supabase/migrations/202608220018_fit_v014_private_function_acl_hardening.sql",
  "supabase/migrations/202608230019_profile_draft_freeze_capability.sql",
  "supabase/migrations/202608230020_profile_frozen_fork_capability.sql",
  "supabase/migrations/202608230021_profile_hosted_auth_subject_compatibility.sql",
  "supabase/migrations/202608230022_profile_taxonomy_projection.sql",
  "supabase/migrations/202608230023_profile_taxonomy_options.sql",
  "supabase/migrations/202608230024_profile_taxonomy_admissibility.sql"
]);

export const MIGRATIONS_001_025 = Object.freeze([
  ...MIGRATIONS_001_024,
  "supabase/migrations/202608250025_profile_frozen_discovery.sql"
]);

export const MIGRATIONS_001_026 = Object.freeze([
  ...MIGRATIONS_001_025,
  "supabase/migrations/202608250026_eligibility_production_assembly_capability.sql"
]);

export const MIGRATIONS_001_027 = Object.freeze([
  ...MIGRATIONS_001_026,
  "supabase/migrations/202608250027_fit_intent_product_capability.sql"
]);

export const MIGRATIONS_001_028 = Object.freeze([
  ...MIGRATIONS_001_027,
  "supabase/migrations/202608260028_fit_product_manifest_compatibility_registration.sql"
]);

export const MIGRATIONS_001_029 = Object.freeze([
  ...MIGRATIONS_001_028,
  "supabase/migrations/202608260029_fit_intent_privacy_deletion_compatibility.sql"
]);

export const SQL_TESTS_001_016 = Object.freeze([
  "supabase/tests/001_education_foundation.sql",
  "supabase/tests/002_phase2_eligibility.sql",
  "supabase/tests/003_phase3_fit.sql",
  "supabase/tests/004_phase012_foundation_hardening.sql",
  "supabase/tests/005_phase013_eligibility_v02.sql",
  "supabase/tests/006_phase014_financial_billing_basis_hardening.sql",
  "supabase/tests/007_phase015_fit_replay_and_seal_hardening.sql",
  "supabase/tests/008_phase016_fit_engine_production_registration.sql",
  "supabase/tests/009_phase017_fit_financial_normalization_workflow.sql",
  "supabase/tests/010_phase018_fit_v014_private_function_acl_hardening.sql",
  "supabase/tests/011_phase019_profile_draft_freeze_capability.sql",
  "supabase/tests/012_phase020_profile_frozen_fork_capability.sql",
  "supabase/tests/013_phase021_profile_hosted_auth_subject_compatibility.sql",
  "supabase/tests/014_phase022_profile_taxonomy_projection.sql",
  "supabase/tests/015_phase023_profile_taxonomy_options.sql",
  "supabase/tests/016_phase024_profile_taxonomy_admissibility.sql"
]);

export const SQL_TESTS_001_017 = Object.freeze([
  ...SQL_TESTS_001_016,
  "supabase/tests/017_phase025_profile_frozen_discovery.sql"
]);

export const SQL_TESTS_001_018 = Object.freeze([
  ...SQL_TESTS_001_017,
  "supabase/tests/018_phase026_eligibility_production_assembly.sql"
]);

export const SQL_TESTS_001_019 = Object.freeze([
  ...SQL_TESTS_001_018,
  "supabase/tests/019_phase027_fit_intent_product_capability.sql"
]);

export const SQL_TESTS_001_020 = Object.freeze([
  ...SQL_TESTS_001_019,
  "supabase/tests/020_phase028_fit_product_manifest_compatibility_registration.sql"
]);

export const SQL_TESTS_001_021 = Object.freeze([
  ...SQL_TESTS_001_020,
  "supabase/tests/021_phase029_fit_intent_privacy_deletion_compatibility.sql"
]);

const orderedSqlFiles = Object.freeze([
  ...MIGRATIONS_001_024.slice(0, 13),
  ...SQL_TESTS_001_016.slice(0, 5),
  MIGRATIONS_001_024[13],
  SQL_TESTS_001_016[0],
  SQL_TESTS_001_016[1],
  SQL_TESTS_001_016[5],
  MIGRATIONS_001_024[14],
  SQL_TESTS_001_016[6],
  MIGRATIONS_001_024[15],
  SQL_TESTS_001_016[7],
  MIGRATIONS_001_024[16],
  SQL_TESTS_001_016[8],
  MIGRATIONS_001_024[17],
  SQL_TESTS_001_016[9],
  MIGRATIONS_001_024[18],
  SQL_TESTS_001_016[10],
  MIGRATIONS_001_024[19],
  SQL_TESTS_001_016[11],
  MIGRATIONS_001_024[20],
  SQL_TESTS_001_016[12],
  MIGRATIONS_001_024[21],
  SQL_TESTS_001_016[13],
  MIGRATIONS_001_024[22],
  SQL_TESTS_001_016[14],
  MIGRATIONS_001_024[23],
  SQL_TESTS_001_016[15],
  MIGRATIONS_001_025[24],
  SQL_TESTS_001_017[16]
]);

const orderedSqlFiles001018 = Object.freeze([
  ...orderedSqlFiles,
  MIGRATIONS_001_026[25],
  SQL_TESTS_001_018[17]
]);

const orderedSqlFiles001019 = Object.freeze([
  ...orderedSqlFiles001018,
  MIGRATIONS_001_027[26],
  SQL_TESTS_001_019[18]
]);

const orderedSqlFiles001020 = Object.freeze([
  ...orderedSqlFiles001019,
  MIGRATIONS_001_028[27],
  SQL_TESTS_001_020[19]
]);

const orderedSqlFiles001021 = Object.freeze([
  ...orderedSqlFiles001018,
  MIGRATIONS_001_027[26],
  MIGRATIONS_001_028[27],
  SQL_TESTS_001_020[19],
  MIGRATIONS_001_029[28],
  SQL_TESTS_001_019[18],
  SQL_TESTS_001_021[20]
]);

const packagePrerequisite =
  "Dependencies must already be installed from the package's committed lockfile.";
const localSupabasePrerequisite =
  "The exact capibara-education-platform local Supabase stack must be running and disposable.";

export const COMMAND_CATALOG = deepFreeze({
  "preflight.light": {
    kind: "preflight",
    classification: "light",
    diskClass: "light",
    requireDocker: false,
    display: "internal: read-only host disk preflight (minimum 1 GiB)"
  },
  "preflight.heavy": {
    kind: "preflight",
    classification: "light",
    diskClass: "heavy",
    requireDocker: true,
    display: "internal: read-only host disk + Docker health preflight (minimum 8 GiB)"
  },
  "tooling.layered-gate-tests": {
    kind: "spawn",
    classification: "light",
    tool: "node",
    cwd: ".",
    args: ["--test", "scripts/phase4-layered-gates.test.mjs"],
    display: "node --test scripts/phase4-layered-gates.test.mjs"
  },
  "web.profile-contracts-targeted": {
    kind: "spawn",
    classification: "light",
    tool: "pnpm",
    cwd: "apps/web",
    args: [
      "exec", "vitest", "run",
      "src/lib/profile/contracts.test.ts",
      "src/lib/profile/http-boundary.test.ts",
      "src/lib/profile/client.test.ts",
      "src/lib/profile/product-safety.test.ts",
      "tests/source-boundary.test.ts"
    ],
    prerequisites: [packagePrerequisite],
    display: "pnpm exec vitest run <closed Profile contract/security test list>"
  },
  "web.intent-evaluation-contracts-targeted": {
    kind: "spawn",
    classification: "light",
    tool: "pnpm",
    cwd: "apps/web",
    args: [
      "exec", "vitest", "run",
      "src/lib/intent/contracts.test.ts",
      "src/lib/intent/service.test.ts",
      "src/lib/intent/http-boundary.test.ts",
      "src/lib/intent/client.test.ts",
      "src/lib/evaluation/contracts.test.ts",
      "src/lib/evaluation/service.test.ts",
      "src/lib/evaluation/http-boundary.test.ts",
      "tests/source-boundary.test.ts"
    ],
    prerequisites: [packagePrerequisite],
    display: "pnpm exec vitest run <closed M027 Intent/Fit orchestration test list>"
  },
  "repo.diff-check": {
    kind: "spawn",
    classification: "light",
    tool: "git",
    cwd: ".",
    args: ["diff", "--check"],
    display: "git diff --check"
  },
  "db.pg15-clean-001-024-non-super": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 15,
    scenario: "non-super-clean",
    prerequisites: ["Docker image postgres:15 is available locally."],
    display: "disposable postgres:15 -> existing _phase024_non_super_runner_regression.sh"
  },
  "db.pg17-clean-001-024-non-super": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 17,
    scenario: "non-super-clean",
    prerequisites: ["Docker image postgres:17 is available locally."],
    display: "disposable postgres:17 -> existing _phase024_non_super_runner_regression.sh"
  },
  "db.pg15-clean-001-025-non-super": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 15,
    scenario: "non-super-clean",
    prerequisites: ["Docker image postgres:15 is available locally."],
    display: "disposable postgres:15 -> migrations 001-025 through the existing non-super runner"
  },
  "db.pg17-clean-001-025-non-super": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 17,
    scenario: "non-super-clean",
    prerequisites: ["Docker image postgres:17 is available locally."],
    display: "disposable postgres:17 -> migrations 001-025 through the existing non-super runner"
  },
  "db.pg15-clean-001-026-non-super": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 15,
    scenario: "non-super-clean",
    prerequisites: ["Docker image postgres:15 is available locally."],
    display: "disposable postgres:15 -> migrations 001-026 through the existing non-super runner"
  },
  "db.pg17-clean-001-026-non-super": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 17,
    scenario: "non-super-clean",
    prerequisites: ["Docker image postgres:17 is available locally."],
    display: "disposable postgres:17 -> migrations 001-026 through the existing non-super runner"
  },
  "db.pg15-clean-001-027-non-super": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 15,
    scenario: "non-super-clean",
    prerequisites: ["Docker image postgres:15 is available locally."],
    display: "disposable postgres:15 -> migrations 001-027 through the existing non-super runner"
  },
  "db.pg17-clean-001-027-non-super": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 17,
    scenario: "non-super-clean",
    prerequisites: ["Docker image postgres:17 is available locally."],
    display: "disposable postgres:17 -> migrations 001-027 through the existing non-super runner"
  },
  "db.pg15-clean-001-028-non-super": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 15,
    scenario: "non-super-clean",
    prerequisites: ["Docker image postgres:15 is available locally."],
    display: "disposable postgres:15 -> migrations 001-028 through the existing non-super runner"
  },
  "db.pg17-clean-001-028-non-super": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 17,
    scenario: "non-super-clean",
    prerequisites: ["Docker image postgres:17 is available locally."],
    display: "disposable postgres:17 -> migrations 001-028 through the existing non-super runner"
  },
  "db.pg15-clean-001-029-non-super": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 15,
    scenario: "non-super-clean",
    prerequisites: ["Docker image postgres:15 is available locally."],
    display: "disposable postgres:15 -> migrations 001-029 through the existing non-super runner"
  },
  "db.pg17-clean-001-029-non-super": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 17,
    scenario: "non-super-clean",
    prerequisites: ["Docker image postgres:17 is available locally."],
    display: "disposable postgres:17 -> migrations 001-029 through the existing non-super runner"
  },
  "db.ordered-sql-001-016": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 15,
    scenario: "sql-files",
    files: orderedSqlFiles,
    prerequisites: ["Docker image postgres:15 is available locally."],
    display: "disposable postgres:15 -> ordered migration/test boundary sequence 001-016"
  },
  "db.ordered-sql-001-017": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 15,
    scenario: "sql-files",
    files: orderedSqlFiles,
    prerequisites: ["Docker image postgres:15 is available locally."],
    display: "disposable postgres:15 -> ordered migration/test boundary sequence 001-017"
  },
  "db.ordered-sql-001-018": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 15,
    scenario: "sql-files",
    files: orderedSqlFiles001018,
    prerequisites: ["Docker image postgres:15 is available locally."],
    display: "disposable postgres:15 -> ordered migration/test boundary sequence 001-018"
  },
  "db.ordered-sql-001-019": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 15,
    scenario: "sql-files",
    files: orderedSqlFiles001019,
    prerequisites: ["Docker image postgres:15 is available locally."],
    display: "disposable postgres:15 -> ordered migration/test boundary sequence 001-019"
  },
  "db.ordered-sql-001-020": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 15,
    scenario: "sql-files",
    files: orderedSqlFiles001020,
    prerequisites: ["Docker image postgres:15 is available locally."],
    display: "disposable postgres:15 -> ordered migration/test boundary sequence 001-020"
  },
  "db.ordered-sql-001-021": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 15,
    scenario: "sql-files",
    files: orderedSqlFiles001021,
    prerequisites: ["Docker image postgres:15 is available locally."],
    display: "disposable postgres:15 -> ordered migration/test boundary sequence 001-021"
  },
  "db.phase024-populated-023-024": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 15,
    scenario: "sql-files",
    files: [
      ...MIGRATIONS_001_024.slice(0, 23),
      "supabase/tests/_phase024_populated_upgrade_fixture.sql",
      MIGRATIONS_001_024[23],
      "supabase/tests/_phase024_populated_upgrade_assert.sql"
    ],
    prerequisites: ["Docker image postgres:15 is available locally."],
    display: "disposable postgres:15 -> populated 023 fixture -> Migration 024 -> existing assertion"
  },
  "db.phase025-populated-024-025": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 15,
    scenario: "sql-files",
    files: [
      ...MIGRATIONS_001_024,
      "supabase/tests/_phase025_populated_upgrade_fixture.sql",
      MIGRATIONS_001_025[24],
      "supabase/tests/_phase025_populated_upgrade_assert.sql"
    ],
    prerequisites: ["Docker image postgres:15 is available locally."],
    display: "disposable postgres:15 -> populated 024 fixture -> Migration 025 -> assertion"
  },
  "db.phase026-populated-025-026": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 15,
    scenario: "sql-files",
    files: [
      ...MIGRATIONS_001_025,
      "supabase/tests/_phase026_populated_upgrade_fixture.sql",
      MIGRATIONS_001_026[25],
      "supabase/tests/_phase026_populated_upgrade_assert.sql"
    ],
    prerequisites: ["Docker image postgres:15 is available locally."],
    display: "disposable postgres:15 -> populated 025 fixture -> Migration 026 -> assertion"
  },
  "db.phase027-populated-026-027": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 15,
    scenario: "sql-files",
    files: [
      ...MIGRATIONS_001_026,
      "supabase/tests/_phase027_populated_upgrade_fixture.sql",
      MIGRATIONS_001_027[26],
      "supabase/tests/_phase027_populated_upgrade_assert.sql"
    ],
    prerequisites: ["Docker image postgres:15 is available locally."],
    display: "disposable postgres:15 -> populated 026 fixture -> Migration 027 -> assertion"
  },
  "db.phase028-populated-027-028": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 15,
    scenario: "sql-files",
    files: [
      ...MIGRATIONS_001_027,
      "supabase/tests/_phase028_populated_upgrade_fixture.sql",
      MIGRATIONS_001_028[27],
      "supabase/tests/_phase028_populated_upgrade_assert.sql"
    ],
    prerequisites: ["Docker image postgres:15 is available locally."],
    display: "disposable postgres:15 -> populated 027 capture -> Migration 028 -> legacy/build assertion"
  },
  "db.phase029-populated-028-029": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 15,
    scenario: "sql-files",
    files: [
      ...MIGRATIONS_001_028,
      "supabase/tests/_phase029_populated_upgrade_fixture.sql",
      MIGRATIONS_001_029[28],
      "supabase/tests/_phase029_populated_upgrade_assert.sql"
    ],
    prerequisites: ["Docker image postgres:15 is available locally."],
    display: "disposable postgres:15 -> populated M027 state at 028 -> Migration 029 -> zero-residue assertion"
  },
  "db.phase024-behavior-security-privacy": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 15,
    scenario: "sql-files",
    files: [...MIGRATIONS_001_024, SQL_TESTS_001_016[15]],
    prerequisites: ["Docker image postgres:15 is available locally."],
    display: "disposable postgres:15 -> migrations 001-024 -> existing test 016"
  },
  "db.phase025-discovery-security-privacy": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 15,
    scenario: "sql-files",
    files: [...MIGRATIONS_001_025, SQL_TESTS_001_017[16]],
    prerequisites: ["Docker image postgres:15 is available locally."],
    display: "disposable postgres:15 -> migrations 001-025 -> test 017 discovery/security/privacy"
  },
  "db.phase026-assembly-security-privacy": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 17,
    scenario: "sql-files",
    files: [...MIGRATIONS_001_026, SQL_TESTS_001_018[17]],
    prerequisites: ["Docker image postgres:17 is available locally."],
    display: "disposable postgres:17 -> migrations 001-026 -> M026 behavior/security/idempotency/privacy"
  },
  "db.phase027-intent-security-privacy": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 17,
    scenario: "sql-files",
    files: [...MIGRATIONS_001_029, SQL_TESTS_001_019[18]],
    prerequisites: ["Docker image postgres:17 is available locally."],
    display: "disposable postgres:17 -> migrations 001-029 -> M027 behavior/security/idempotency/privacy after forward compatibility repair"
  },
  "db.phase028-product-build-registration": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 17,
    scenario: "sql-files",
    files: [...MIGRATIONS_001_028, SQL_TESTS_001_020[19]],
    prerequisites: ["Docker image postgres:17 is available locally."],
    display: "disposable postgres:17 -> migrations 001-028 -> product build identity/ACL test 020"
  },
  "db.phase029-intent-privacy-compatibility": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 17,
    scenario: "sql-files",
    files: [...MIGRATIONS_001_029, SQL_TESTS_001_021[20]],
    prerequisites: ["Docker image postgres:17 is available locally."],
    display: "disposable postgres:17 -> migrations 001-029 -> M027 privacy compatibility/adversarial test 021"
  },
  "db.phase027-intent-concurrency": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 17,
    scenario: "sql-files",
    files: [...MIGRATIONS_001_027, "supabase/tests/_phase027_concurrency_probe.sql"],
    prerequisites: ["Docker image postgres:17 is available locally."],
    display: "disposable postgres:17 -> migrations 001-027 -> M027 concurrency probe"
  },
  "db.phase029-privacy-concurrency": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 17,
    scenario: "sql-files",
    files: [
      ...MIGRATIONS_001_029,
      "supabase/tests/_phase029_privacy_concurrency_probe.sql"
    ],
    prerequisites: ["Docker image postgres:17 is available locally."],
    display: "disposable postgres:17 -> migrations 001-029 -> privacy deletion versus mutate/freeze/evaluation concurrency"
  },
  "db.phase024-definition-concurrency": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 17,
    scenario: "sql-files",
    files: [...MIGRATIONS_001_024, "supabase/tests/_phase024_concurrency_probe.sql"],
    prerequisites: ["Docker image postgres:17 is available locally."],
    display: "disposable postgres:17 -> migrations 001-024 -> existing Phase 024 concurrency probe"
  },
  "db.phase020-profile-fork-concurrency": {
    kind: "docker-postgres",
    classification: "heavy",
    major: 17,
    scenario: "sql-files",
    files: [...MIGRATIONS_001_024, "supabase/tests/_phase020_fork_concurrency_probe.sql"],
    prerequisites: ["Docker image postgres:17 is available locally."],
    display: "disposable postgres:17 -> migrations 001-024 -> existing Phase 020 fork concurrency probe"
  },
  "db.supabase-reset-001-024": {
    kind: "spawn",
    classification: "heavy",
    tool: "supabase",
    cwd: ".",
    args: ["db", "reset", "--local"],
    prerequisites: [localSupabasePrerequisite],
    display: "supabase db reset --local"
  },
  "db.supabase-reset-001-025": {
    kind: "spawn",
    classification: "heavy",
    tool: "supabase",
    cwd: ".",
    args: ["db", "reset", "--local"],
    prerequisites: [localSupabasePrerequisite],
    display: "supabase db reset --local (migrations 001-025)"
  },
  "db.supabase-reset-001-026": {
    kind: "spawn",
    classification: "heavy",
    tool: "supabase",
    cwd: ".",
    args: ["db", "reset", "--local"],
    prerequisites: [localSupabasePrerequisite],
    display: "supabase db reset --local (migrations 001-026)"
  },
  "db.supabase-reset-001-027": {
    kind: "spawn",
    classification: "heavy",
    tool: "supabase",
    cwd: ".",
    args: ["db", "reset", "--local"],
    prerequisites: [localSupabasePrerequisite],
    display: "supabase db reset --local (migrations 001-027)"
  },
  "db.supabase-reset-001-028": {
    kind: "spawn",
    classification: "heavy",
    tool: "supabase",
    cwd: ".",
    args: ["db", "reset", "--local"],
    prerequisites: [localSupabasePrerequisite],
    display: "supabase db reset --local (migrations 001-028)"
  },
  "db.supabase-reset-001-029": {
    kind: "spawn",
    classification: "heavy",
    tool: "supabase",
    cwd: ".",
    args: ["db", "reset", "--local"],
    prerequisites: [localSupabasePrerequisite],
    display: "supabase db reset --local (migrations 001-029)"
  },
  "db.local-auth-postgrest-profile-matrix": {
    kind: "local-auth-sequence",
    classification: "heavy",
    scripts: [
      "supabase/tests/_phase021_local_auth_postgrest_e2e.mjs",
      "supabase/tests/_phase022_local_auth_postgrest_e2e.mjs",
      "supabase/tests/_phase023_local_auth_postgrest_e2e.mjs",
      "supabase/tests/_phase024_local_auth_postgrest_e2e.mjs",
      "supabase/tests/_phase025_local_auth_postgrest_e2e.mjs"
    ],
    prerequisites: [localSupabasePrerequisite],
    display: "node <closed Phase 021-025 local Auth/PostgREST E2E sequence>"
  },
  "db.local-auth-restart-phase024": {
    kind: "local-auth-restart",
    classification: "heavy",
    script: "supabase/tests/_phase024_local_auth_postgrest_e2e.mjs",
    prerequisites: [localSupabasePrerequisite],
    display: "restart exact local Auth container -> wait healthy -> existing Phase 024 E2E"
  },
  "db.local-auth-restart-phase025": {
    kind: "local-auth-restart",
    classification: "heavy",
    script: "supabase/tests/_phase025_local_auth_postgrest_e2e.mjs",
    prerequisites: [localSupabasePrerequisite],
    display: "restart exact local Auth container -> wait healthy -> Phase 025 E2E"
  },
  "db.local-auth-postgrest-phase026": {
    kind: "local-auth-sequence",
    classification: "heavy",
    scripts: ["supabase/tests/_phase026_local_auth_postgrest_e2e.mjs"],
    prerequisites: [localSupabasePrerequisite],
    display: "node Phase 026 real Auth/JWT/PostgREST concurrent assembly E2E"
  },
  "db.local-auth-restart-phase026": {
    kind: "local-auth-restart",
    classification: "heavy",
    script: "supabase/tests/_phase026_local_auth_postgrest_e2e.mjs",
    prerequisites: [localSupabasePrerequisite],
    display: "restart exact local Auth container -> wait healthy -> Phase 026 assembly E2E"
  },
  "db.local-auth-postgrest-phase027": {
    kind: "local-auth-sequence",
    classification: "heavy",
    scripts: ["supabase/tests/_phase027_local_auth_postgrest_e2e.mjs"],
    prerequisites: [localSupabasePrerequisite],
    display: "node Phase 027 real Auth/JWT/PostgREST Intent lifecycle and assembly E2E"
  },
  "db.local-auth-restart-phase027": {
    kind: "local-auth-restart",
    classification: "heavy",
    script: "supabase/tests/_phase027_local_auth_postgrest_e2e.mjs",
    prerequisites: [localSupabasePrerequisite],
    display: "restart exact local Auth container -> wait healthy -> Phase 027 Intent E2E"
  },
  "backend.eligibility-full": {
    kind: "spawn",
    classification: "heavy",
    tool: "npm",
    cwd: "packages/eligibility-engine",
    args: ["test"],
    prerequisites: [packagePrerequisite],
    display: "npm test (packages/eligibility-engine)"
  },
  "backend.fit-full": {
    kind: "spawn",
    classification: "heavy",
    tool: "pnpm",
    cwd: "packages/fit-engine",
    args: ["test"],
    prerequisites: [packagePrerequisite],
    display: "pnpm test (packages/fit-engine)"
  },
  "backend.adapter-full": {
    kind: "spawn",
    classification: "heavy",
    tool: "pnpm",
    cwd: "packages/fit-engine-adapter",
    args: ["test"],
    prerequisites: [packagePrerequisite],
    display: "pnpm test (packages/fit-engine-adapter)"
  },
  "edge.http-boundary-full": {
    kind: "spawn",
    classification: "light",
    tool: "node",
    cwd: ".",
    args: ["--test", "supabase/functions/_shared/http-boundary.test.mjs"],
    display: "node --test supabase/functions/_shared/http-boundary.test.mjs"
  },
  "ops.minimum-beta-tooling-full": {
    kind: "spawn",
    classification: "light",
    tool: "node",
    cwd: ".",
    args: [
      "--test",
      "scripts/phase4a2-minimum-beta-ops.test.mjs",
      "scripts/phase4a2-minimum-beta-sql.test.mjs"
    ],
    display: "node --test <closed Phase 4A-2 local tooling test list>"
  },
  "web.unit-contract-security-full": {
    kind: "spawn",
    classification: "heavy",
    tool: "pnpm",
    cwd: "apps/web",
    args: ["test"],
    prerequisites: [packagePrerequisite],
    display: "pnpm test (apps/web)"
  },
  "web.browser-auth-profile-full": {
    kind: "spawn",
    classification: "heavy",
    tool: "pnpm",
    cwd: "apps/web",
    args: ["test:browser"],
    prerequisites: [packagePrerequisite, "The committed Playwright browser version is installed."],
    display: "pnpm test:browser (apps/web)"
  },
  "web.real-local-profile-lifecycle": {
    kind: "spawn",
    classification: "heavy",
    tool: "pnpm",
    cwd: "apps/web",
    args: ["exec", "playwright", "test", "--config", "playwright.real-local.config.ts"],
    prerequisites: [packagePrerequisite, localSupabasePrerequisite, "The committed Playwright browser version is installed."],
    display: "pnpm exec playwright test --config playwright.real-local.config.ts"
  },
  "web.lint-full": {
    kind: "spawn",
    classification: "light",
    tool: "pnpm",
    cwd: "apps/web",
    args: ["lint"],
    prerequisites: [packagePrerequisite],
    display: "pnpm lint (apps/web)"
  },
  "web.typecheck-full": {
    kind: "spawn",
    classification: "light",
    tool: "pnpm",
    cwd: "apps/web",
    args: ["typecheck"],
    prerequisites: [packagePrerequisite],
    display: "pnpm typecheck (apps/web)"
  },
  "web.production-build-full": {
    kind: "spawn",
    classification: "heavy",
    tool: "pnpm",
    cwd: "apps/web",
    args: ["build"],
    prerequisites: [packagePrerequisite],
    display: "pnpm build (apps/web)"
  },
  "web.source-secret-fixture-boundary": {
    kind: "spawn",
    classification: "light",
    tool: "pnpm",
    cwd: "apps/web",
    args: ["exec", "vitest", "run", "tests/source-boundary.test.ts"],
    prerequisites: [packagePrerequisite],
    display: "pnpm exec vitest run tests/source-boundary.test.ts"
  },
  "web.semantic-no-ai-guards": {
    kind: "spawn",
    classification: "light",
    tool: "pnpm",
    cwd: "apps/web",
    args: ["exec", "vitest", "run", "src/lib/profile/product-safety.test.ts"],
    prerequisites: [packagePrerequisite],
    display: "pnpm exec vitest run src/lib/profile/product-safety.test.ts"
  },
  "fit.runtime-reproducibility": {
    kind: "runtime-reproducibility",
    classification: "heavy",
    prerequisites: [packagePrerequisite],
    display: "pnpm bundle:edge -> SHA-256 frozen runtime verification"
  },
  "repo.frozen-invariant-audit": {
    kind: "frozen-audit",
    classification: "light",
    display: "internal: Migration 001-026 + semantic/Edge/evaluator/fingerprint/runtime drift audit"
  },
  "release.remote-migration-history-readonly": {
    kind: "spawn",
    classification: "heavy",
    tool: "supabase",
    cwd: ".",
    args: ["migration", "list", "--linked"],
    prerequisites: ["Supabase CLI is authenticated and linked to the intended project."],
    display: "supabase migration list --linked (read-only)"
  },
  "release.minimum-beta-ops-readonly": {
    kind: "release-ops",
    classification: "heavy",
    prerequisites: [
      "PHASE4_RELEASE_PROJECT_REF is a validated 20-character Supabase project reference.",
      "SUPABASE_ACCESS_TOKEN is present only in process environment memory."
    ],
    display: "node scripts/phase4a2-minimum-beta-ops.mjs --project-ref <validated-env> --include-database"
  },
  "release.deployment-authorization-hold": {
    kind: "authorization-hold",
    classification: "heavy",
    code: "RELEASE_DEPLOYMENT_NOT_AUTHORIZED",
    display: "authorization hold: deployment mutation"
  },
  "release.remote-smoke-authorization-hold": {
    kind: "authorization-hold",
    classification: "heavy",
    code: "RELEASE_REMOTE_SMOKE_NOT_AUTHORIZED",
    display: "authorization hold: hosted smoke traffic/data lifecycle"
  },
  "release.rollback-readiness-hold": {
    kind: "authorization-hold",
    classification: "heavy",
    code: "RELEASE_ROLLBACK_READINESS_NOT_REVIEWED",
    display: "authorization hold: rollback/readiness decision"
  }
});

export const GATE_REQUIRED_ORDERS = Object.freeze({
  FAST: Object.freeze([
    "preflight.light",
    "tooling.layered-gate-tests",
    "web.intent-evaluation-contracts-targeted",
    "web.profile-contracts-targeted",
    "repo.diff-check"
  ]),
  RELEVANT: Object.freeze([
    "preflight.heavy",
    "db.pg17-clean-001-029-non-super",
    "db.phase027-intent-security-privacy",
    "db.phase028-product-build-registration",
    "db.phase029-intent-privacy-compatibility",
    "db.phase028-populated-027-028",
    "db.phase029-populated-028-029",
    "db.phase029-privacy-concurrency",
    "db.supabase-reset-001-029",
    "db.local-auth-postgrest-phase027",
    "backend.fit-full",
    "backend.adapter-full",
    "web.real-local-profile-lifecycle",
    "web.intent-evaluation-contracts-targeted",
    "fit.runtime-reproducibility",
    "repo.diff-check"
  ]),
  BASELINE: Object.freeze([
    "preflight.heavy",
    "db.pg15-clean-001-029-non-super",
    "db.pg17-clean-001-029-non-super",
    "db.ordered-sql-001-021",
    "db.phase024-populated-023-024",
    "db.phase025-populated-024-025",
    "db.phase026-populated-025-026",
    "db.phase027-populated-026-027",
    "db.phase028-populated-027-028",
    "db.phase029-populated-028-029",
    "db.supabase-reset-001-029",
    "db.phase024-behavior-security-privacy",
    "db.phase025-discovery-security-privacy",
    "db.phase026-assembly-security-privacy",
    "db.phase027-intent-security-privacy",
    "db.phase028-product-build-registration",
    "db.phase029-intent-privacy-compatibility",
    "db.phase024-definition-concurrency",
    "db.phase020-profile-fork-concurrency",
    "db.phase027-intent-concurrency",
    "db.phase029-privacy-concurrency",
    "db.local-auth-postgrest-profile-matrix",
    "db.local-auth-postgrest-phase026",
    "db.local-auth-restart-phase026",
    "db.local-auth-postgrest-phase027",
    "db.local-auth-restart-phase027",
    "backend.eligibility-full",
    "backend.fit-full",
    "backend.adapter-full",
    "edge.http-boundary-full",
    "ops.minimum-beta-tooling-full",
    "web.unit-contract-security-full",
    "web.browser-auth-profile-full",
    "web.real-local-profile-lifecycle",
    "web.intent-evaluation-contracts-targeted",
    "web.lint-full",
    "web.typecheck-full",
    "web.production-build-full",
    "web.source-secret-fixture-boundary",
    "web.semantic-no-ai-guards",
    "fit.runtime-reproducibility",
    "repo.frozen-invariant-audit",
    "repo.diff-check"
  ]),
  RELEASE: Object.freeze([
    "release.remote-migration-history-readonly",
    "release.minimum-beta-ops-readonly",
    "release.deployment-authorization-hold",
    "release.remote-smoke-authorization-hold",
    "release.rollback-readiness-hold"
  ])
});

export const FROZEN_AUDIT_PATHS = Object.freeze([
  ...MIGRATIONS_001_027,
  "packages/eligibility-engine/src",
  "packages/fit-engine/src",
  "supabase/functions/fit-normalization-prepare",
  "supabase/functions/fit-normalization-review",
  "supabase/functions/fit-normalization-resume",
  "supabase/functions/_shared/http-boundary.js"
]);

export const LOCAL_AUTH_DB_CONTAINER = "supabase_db_capibara-education-platform";
export const LOCAL_AUTH_CONTAINER = "supabase_auth_capibara-education-platform";
