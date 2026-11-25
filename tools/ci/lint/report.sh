#!/usr/bin/env bash
# Runs one linter; findings block only when LINT_STRICT=1, otherwise they become warnings.
set -euo pipefail

usage() { echo "usage: report.sh [--dry-run] <name> -- <command...>" >&2; exit 2; }

dry_run=0
if [ "${1:-}" = "--dry-run" ]; then dry_run=1; shift; fi
if [ $# -lt 3 ] || [ "$2" != "--" ]; then usage; fi
name=$1
shift 2

if [ "$dry_run" = 1 ]; then
  echo "lint ${name} (strict=${LINT_STRICT:-0}): would run: $*"
  exit 0
fi

if ! command -v "$1" >/dev/null 2>&1; then
  echo "skip ${name}: $1 is not installed"
  exit 0
fi

status=0
"$@" || status=$?
if [ "$status" -eq 0 ]; then
  echo "lint ${name}: clean"
  exit 0
fi
if [ "${LINT_STRICT:-0}" = 1 ]; then
  echo "lint ${name}: findings (blocking, LINT_STRICT=1)"
  exit "$status"
fi
echo "::warning title=${name}::findings in report mode; set LINT_STRICT=1 to block"
exit 0
