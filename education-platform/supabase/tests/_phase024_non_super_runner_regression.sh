#!/usr/bin/env bash
set -Eeuo pipefail

# Run only inside a fresh disposable PostgreSQL 15 or 17 container. The cluster
# administrator provisions hosted primitives; every project migration then
# runs as the database-owning, CREATEROLE, non-superuser login below.

readonly workspace_root="${1:-/workspace}"
readonly admin_user="${PHASE024_ADMIN_USER:-postgres}"
readonly database_name="${PHASE024_DATABASE:-postgres}"
readonly runner_role="phase024_non_super_runner"

psql -X -U "${admin_user}" -d "${database_name}" -v ON_ERROR_STOP=1 \
  -c "create role ${runner_role} login nosuperuser createdb createrole nobypassrls; alter database ${database_name} owner to ${runner_role};"

psql -X -q -U "${admin_user}" -d "${database_name}" \
  -v ON_ERROR_STOP=1 \
  -f "${workspace_root}/supabase/tests/_bootstrap_local.sql"
psql -X -q -U "${admin_user}" -d "${database_name}" \
  -v ON_ERROR_STOP=1 \
  -c "grant usage on schema auth to ${runner_role}; grant select, references on auth.users to ${runner_role}; grant execute on function auth.uid() to ${runner_role};"

run_sql() {
  local sql_file="$1"
  psql -X -q -U "${runner_role}" -d "${database_name}" \
    -v ON_ERROR_STOP=1 -f "${sql_file}"
}

for migration in "${workspace_root}"/supabase/migrations/*.sql; do
  run_sql "${migration}"
done

run_sql "${workspace_root}/supabase/tests/_phase024_non_super_runner_assert.sql"
