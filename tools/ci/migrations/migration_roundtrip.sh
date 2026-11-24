#!/usr/bin/env bash
# Applies every migration up, then the new ones down, then up again on a scratch database.
# Usage: migration_roundtrip.sh [--dry-run] MIGRATIONS_ROOT [NEW_DIR...]; the server comes from PGHOST, PGUSER and PGPASSWORD.
# Plain psql, not diesel_cli: a cargo build of diesel_cli costs minutes and the up.sql/down.sql files are plain SQL;
# a directory runs in one transaction unless metadata.toml says run_in_transaction = false, as Diesel does.
set -euo pipefail

dry=0
if [ "${1:-}" = "--dry-run" ]; then dry=1; shift; fi
root="${1:?migrations root is required}"
shift
new=("$@")
db="roundtrip_$(basename "$(dirname "$root")" | tr -c 'a-z0-9\n' '_')"

run() { if [ "$dry" = 1 ]; then echo "+ $*"; else "$@"; fi; }

apply() { # apply DIR up|down
  local dir="$root/$1" file="$2.sql" flags=(-X -q -v ON_ERROR_STOP=1 -d "$db")
  [ -f "$dir/$file" ] || { echo "missing $dir/$file" >&2; exit 1; }
  grep -Eq '^[[:space:]]*run_in_transaction[[:space:]]*=[[:space:]]*false' "$dir/metadata.toml" 2>/dev/null || flags+=(--single-transaction)
  echo "$2 $1"
  run psql "${flags[@]}" -f "$dir/$file"
}

mapfile -t all < <(find "$root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort)

# a rerun starts from an empty database
run psql -X -q -v ON_ERROR_STOP=1 -d postgres -c "DROP DATABASE IF EXISTS \"$db\"" -c "CREATE DATABASE \"$db\""
for d in "${all[@]}"; do apply "$d" up; done
for ((i = ${#new[@]} - 1; i >= 0; i--)); do apply "${new[i]}" down; done
for d in "${new[@]}"; do apply "$d" up; done
echo "roundtrip ok: ${#all[@]} migrations, ${#new[@]} reversed and reapplied"
