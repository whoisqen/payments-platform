#!/usr/bin/env bash
# Batched backfill outside the deploy hook: each backfill/*.sql runs with :batch_size until it changes no row,
# pausing while an Aurora reader lags more than BACKFILL_MAX_REPLICA_LAG_MS. Usage: backfill.sh [--dry-run]
set -euo pipefail

dir=${BACKFILL_DIR:-/opt/migrator/backfill}
batch=${BACKFILL_BATCH_SIZE:-10000}
max_lag=${BACKFILL_MAX_REPLICA_LAG_MS:-500}
[[ $batch =~ ^[0-9]+$ && $max_lag =~ ^[0-9]+$ ]] || { echo "batch size and lag must be numbers" >&2; exit 2; }
shopt -s nullglob
files=("$dir"/*.sql)
if [ "${#files[@]}" -eq 0 ]; then echo '{"event":"nothing-to-backfill"}'; exit 0; fi
if [ "${1:-}" = --dry-run ]; then printf '{"event":"would-backfill","file":"%s"}\n' "${files[@]}"; exit 0; fi

if [ -z "${PGPASSWORD:-}" ]; then
  PGPASSWORD=$(aws rds generate-db-auth-token --hostname "$PGHOST" --port "${PGPORT:-5432}" --username "$PGUSER" --region "${AWS_REGION:?}")
  export PGPASSWORD
fi
q() { psql -X -q -t -A -v ON_ERROR_STOP=1 "$@"; }

for f in "${files[@]}"; do
  total=0
  while :; do
    lag=$(q -c "select coalesce(max(replica_lag_in_msec), 0)::bigint from aurora_replica_status() where session_id <> 'MASTER_SESSION_ID'")
    if [ "${lag:-0}" -gt "$max_lag" ]; then sleep 5; continue; fi
    # the file ends in a data-changing statement; psql reports its row count as "UPDATE n" or "DELETE n"
    out=$(psql -X -v ON_ERROR_STOP=1 -v "batch_size=${batch}" -f "$f")
    n=$(awk '/^(UPDATE|DELETE|INSERT 0) [0-9]+$/{print $NF}' <<<"$out" | tail -n1)
    total=$((total + ${n:-0}))
    if [ "${n:-0}" -eq 0 ]; then break; fi
  done
  printf '{"event":"backfilled","file":"%s","rows":%d}\n' "$(basename "$f")" "$total"
done
