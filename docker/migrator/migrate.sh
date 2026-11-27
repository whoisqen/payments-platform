#!/usr/bin/env bash
# Runs the pending vendored diesel migrations under one Postgres advisory lock; a second Job waits, a re-run applies nothing.
# Environment: PGHOST PGPORT PGDATABASE PGUSER PGSSLMODE (chart), AWS_REGION, optional PGPASSWORD, MIGRATION_MODE,
# PG_LOCK_TIMEOUT, PG_STATEMENT_TIMEOUT, MIGRATION_LOCK_WAIT. Usage: migrate.sh [--dry-run]
set -euo pipefail

dry_run=false
if [ "${1:-}" = --dry-run ]; then dry_run=true; fi
dir=${MIGRATIONS_DIR:-/opt/migrator/migrations}
mode=${MIGRATION_MODE:-expand-only}
lock_key=${MIGRATION_LOCK_KEY:-726173}
log() { printf '{"event":"%s","database":"%s"%s}\n' "$1" "${PGDATABASE:-}" "${2:+,$2}"; }

for v in PGHOST PGDATABASE PGUSER; do [ -n "${!v:-}" ] || { echo "$v is required" >&2; exit 2; }; done
[[ $mode =~ ^(expand-only|contract)$ ]] || { echo "MIGRATION_MODE must be expand-only or contract" >&2; exit 2; }
[[ $lock_key =~ ^[0-9]+$ ]] || { echo "MIGRATION_LOCK_KEY must be a number" >&2; exit 2; }
[ -d "$dir" ] || { echo "no migrations in $dir" >&2; exit 2; }

if [ -z "${PGPASSWORD:-}" ] && [ "$dry_run" = false ]; then
  # IAM database authentication through the Pod Identity credentials; the token is valid for 15 minutes, enough to connect
  : "${AWS_REGION:?AWS_REGION is required for IAM authentication}"
  PGPASSWORD=$(aws rds generate-db-auth-token --hostname "$PGHOST" --port "${PGPORT:-5432}" --username "$PGUSER" --region "$AWS_REGION")
  export PGPASSWORD
fi

if [ "$dry_run" = true ]; then
  log would-run "\"mode\":\"$mode\",\"migrations\":$(find "$dir" -mindepth 2 -maxdepth 2 -name up.sql | wc -l)"
  exit 0
fi

# the lock lives in its own session, held while diesel runs; lock_timeout of the migrations does not apply to this wait
coproc LOCK { PGOPTIONS="-c statement_timeout=${MIGRATION_LOCK_WAIT:-15min}" psql -X -q -t -A -v ON_ERROR_STOP=1 2>&1; }
release() {
  { echo '\q' >&"${LOCK[1]}"; } 2>/dev/null || true
  wait "$LOCK_PID" 2>/dev/null || true
}
trap release EXIT
echo "select pg_advisory_lock(${lock_key}); select 'locked';" >&"${LOCK[1]}"
line=""
while IFS= read -r line <&"${LOCK[0]}"; do
  if [ "$line" = locked ]; then break; fi
  if [ -n "$line" ]; then log lock-failed "\"error\":\"${line//\"/\'}\""; exit 1; fi
done
[ "$line" = locked ] || { log lock-failed "\"error\":\"the lock session ended\""; exit 1; }
log locked "\"mode\":\"$mode\""

# libpq takes every connection value from the PG* variables, so the URL carries no host, user or token
export PGOPTIONS="-c lock_timeout=${PG_LOCK_TIMEOUT:-5s} -c statement_timeout=${PG_STATEMENT_TIMEOUT:-10min}"
DATABASE_URL=postgresql:// diesel migration run --migration-dir "$dir"
log migrated
