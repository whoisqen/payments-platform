#!/usr/bin/env bash
# Init container of the migration Job: maps the chart environment onto pre-migration-snapshot.sh (D3, FR-DAT-22).
# Environment: SNAPSHOT_STORE SNAPSHOT_LABEL SNAPSHOT_RETENTION_DAYS SNAPSHOT_WAIT_TIMEOUT_SECONDS (chart),
# SNAPSHOT_RESOURCE_ARN SNAPSHOT_VAULT SNAPSHOT_ROLE_ARN AWS_REGION. Usage: snapshot.sh [--dry-run]
set -euo pipefail

for v in SNAPSHOT_STORE SNAPSHOT_LABEL SNAPSHOT_RESOURCE_ARN SNAPSHOT_VAULT AWS_REGION; do
  [ -n "${!v:-}" ] || { echo "$v is required" >&2; exit 2; }
done
# the snapshot script keeps every recovery point 35 days; a different chart value would be silently ignored
[ "${SNAPSHOT_RETENTION_DAYS:-35}" = 35 ] || { echo "SNAPSHOT_RETENTION_DAYS must be 35" >&2; exit 2; }

args=(--store "$SNAPSHOT_STORE" --resource-arn "$SNAPSHOT_RESOURCE_ARN" --label "$SNAPSHOT_LABEL"
  --vault "$SNAPSHOT_VAULT" --region "$AWS_REGION" --wait-seconds "${SNAPSHOT_WAIT_TIMEOUT_SECONDS:-1200}")
if [ -n "${SNAPSHOT_ROLE_ARN:-}" ]; then args+=(--role-arn "$SNAPSHOT_ROLE_ARN"); fi
if [ "${1:-}" = --dry-run ]; then args+=(--dry-run); fi
exec "$(dirname "$0")/pre-migration-snapshot.sh" "${args[@]}"
