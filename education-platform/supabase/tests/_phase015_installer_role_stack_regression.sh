#!/usr/bin/env bash
set -Eeuo pipefail

# Run only inside a fresh disposable PostgreSQL container. This reproduces the
# hosted Supabase role stack in which session_user is a temporary login role
# while current_user is the database-owning migration installer.

readonly workspace_root="${1:-/workspace}"
readonly admin_user="${PHASE015_ADMIN_USER:-postgres}"
readonly database_name="${PHASE015_DATABASE:-postgres}"
readonly login_role="phase015_role_stack_login"
readonly installer_role="phase015_role_stack_installer"

psql -X -U "${admin_user}" -d "${database_name}" -v ON_ERROR_STOP=1 \
  -c "create role ${login_role} login nosuperuser nocreatedb nocreaterole nobypassrls; create role ${installer_role} nologin nosuperuser nocreatedb createrole nobypassrls; grant ${installer_role} to ${login_role}; alter database ${database_name} owner to ${installer_role};"

# Hosted roles/auth primitives pre-exist outside the migration runner's
# authority. The local bootstrap mirrors that boundary and therefore runs as
# the disposable cluster administrator before the dual-role installer path.
psql -X -q -U "${admin_user}" -d "${database_name}" \
  -v ON_ERROR_STOP=1 \
  -f "${workspace_root}/supabase/tests/_bootstrap_local.sql"
psql -X -q -U "${admin_user}" -d "${database_name}" \
  -v ON_ERROR_STOP=1 \
  -c "grant usage on schema auth to ${installer_role}; grant select, references on auth.users to ${installer_role}; grant execute on function auth.uid() to ${installer_role};"

export PGOPTIONS="-c role=${installer_role}"

run_sql() {
  local sql_file="$1"
  psql -X -q -U "${login_role}" -d "${database_name}" \
    -v ON_ERROR_STOP=1 -f "${sql_file}"
}

for migration in "${workspace_root}"/supabase/migrations/2026082000{01..14}_*.sql; do
  run_sql "${migration}"
done

# Keep the post-COMMIT assertion on the same connection as Migration 015. A
# transaction-local role restore is insufficient because the Supabase runner
# records migration history only after the migration's explicit COMMIT.
psql -X -q -U "${login_role}" -d "${database_name}" \
  -v ON_ERROR_STOP=1 \
  -f "${workspace_root}/supabase/migrations/202608200015_fit_replay_and_seal_hardening.sql" \
  -c "select case when session_user = '${login_role}' and current_user = '${installer_role}' then 'PHASE015_POST_COMMIT_ROLE_RESTORE_PASS' else 'PHASE015_POST_COMMIT_ROLE_RESTORE_FAIL' end;"

run_sql "${workspace_root}/supabase/tests/007_phase015_fit_replay_and_seal_hardening.sql"

psql -X -Aqt -U "${login_role}" -d "${database_name}" \
  -v ON_ERROR_STOP=1 \
  -c "select case when session_user = '${login_role}' and current_user = '${installer_role}' and to_regclass('private.fit_evaluation_semantic_pins') is not null then 'PHASE015_INSTALLER_ROLE_STACK_PASS' else 'PHASE015_INSTALLER_ROLE_STACK_FAIL' end;"
