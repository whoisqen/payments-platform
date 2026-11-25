#!/usr/bin/env bash
# Applies the vendored up.sql migrations in order and records each one, so a second run changes nothing.
# usage: migrate.sh [--dry-run] <database>=<migrations-dir> ...   (connection from PGHOST, PGUSER, PGPASSWORD)
set -euo pipefail

dry_run=0
if [ "${1:-}" = "--dry-run" ]; then dry_run=1; shift; fi
[ $# -gt 0 ] || { echo "usage: migrate.sh [--dry-run] <database>=<dir> ..." >&2; exit 2; }

psql_db() { psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}"; }

for pair in "$@"; do
  db=${pair%%=*}
  dir=${pair#*=}
  [[ $db =~ ^[a-z_]+$ ]] || { echo "bad database name: $db" >&2; exit 2; }
  [ -d "$dir" ] || { echo "no migrations directory: $dir" >&2; exit 2; }

  exists=$(psql -X -tA -d postgres -c "select 1 from pg_database where datname = '${db}'")
  if [ "$exists" != 1 ]; then
    if [ "$dry_run" = 1 ]; then echo "would create database ${db}"; else createdb "$db"; fi
  fi
  applied=""
  if [ "$exists" = 1 ] || [ "$dry_run" = 0 ]; then
    psql_db "$db" -c "create table if not exists ci_schema_migrations (version text primary key, applied_at timestamptz not null default now())" >/dev/null 2>&1 || true
    applied=$(psql -X -tA -d "$db" -c "select version from ci_schema_migrations" 2>/dev/null || true)
  fi

  count=0
  while IFS= read -r up; do
    version=$(basename "$(dirname "$up")")
    [[ $version =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "bad migration name: $version" >&2; exit 2; }
    grep -qxF "$version" <<<"$applied" && continue
    count=$((count + 1))
    if [ "$dry_run" = 1 ]; then echo "would apply ${db}: ${version}"; continue; fi
    # like diesel: one transaction per migration unless its metadata.toml opts out
    tx=(-1)
    if grep -qsE '^run_in_transaction *= *false' "$(dirname "$up")/metadata.toml"; then tx=(); fi
    psql_db "$db" "${tx[@]}" -f "$up"
    psql_db "$db" -c "insert into ci_schema_migrations (version) values ('${version}')"
  done < <(find "$dir" -mindepth 2 -maxdepth 2 -name up.sql | sort)
  echo "${db}: ${count} migration(s) $([ "$dry_run" = 1 ] && echo pending || echo applied)"
done
