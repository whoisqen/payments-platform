#!/usr/bin/env bash
# On-demand snapshot before a schema change (D3); exits 0 only when the recovery point is available.
set -euo pipefail

usage() {
  cat <<'EOF'
usage: pre-migration-snapshot.sh --store aurora|dynamodb|clickhouse --resource-arn ARN --label LABEL
       --vault NAME [--role-arn ARN] --region REGION [--wait-seconds N] [--poll-seconds N] [--dry-run]
Starts an AWS Backup job with a 35-day lifecycle (a manual RDS snapshot never expires) tagged change=LABEL.
EOF
}

store="" arn="" label="" vault="" role="" region="" wait=1800 poll=15 dry=0
retention_days=35

while [[ $# -gt 0 ]]; do
  case $1 in
    --store) store=$2; shift 2 ;;
    --resource-arn) arn=$2; shift 2 ;;
    --label) label=$2; shift 2 ;;
    --vault) vault=$2; shift 2 ;;
    --role-arn) role=$2; shift 2 ;;
    --region) region=$2; shift 2 ;;
    --wait-seconds) wait=$2; shift 2 ;;
    --poll-seconds) poll=$2; shift 2 ;;
    --dry-run) dry=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

log() { printf '{"event":"%s","store":"%s","label":"%s"%s}\n' "$1" "$store" "$label" "${2:+,$2}"; }

case $store in
  aurora | dynamodb | clickhouse) ;;
  opensearch) echo "opensearch snapshots go through its snapshot API, not AWS Backup; not supported here" >&2; exit 2 ;;
  *) echo "--store must be aurora, dynamodb or clickhouse" >&2; exit 2 ;;
esac
[[ -n $vault ]] || { echo "--vault is required (the backup vault of the store)" >&2; exit 2; }
[[ -n $region ]] || { echo "--region is required" >&2; exit 2; }
[[ $arn =~ ^arn:aws:[a-z0-9-]+:[a-z0-9-]*:[0-9]{12}: ]] || { echo "--resource-arn is not an ARN" >&2; exit 2; }
[[ $label =~ ^[a-z0-9][a-z0-9-]{2,62}$ ]] || { echo "--label must be kebab-case, 3 to 63 characters" >&2; exit 2; }
[[ $dry -eq 1 || -n $role ]] || { echo "--role-arn is required unless --dry-run" >&2; exit 2; }

# the same change and resource always map to the same token, so a re-run joins the existing job
token=$(printf '%s|%s' "$label" "$arn" | sha256sum | cut -c1-32)

if [[ $dry -eq 1 ]]; then
  log would-start-backup "\"vault\":\"$vault\",\"delete_after_days\":$retention_days,\"token\":\"$token\""
  exit 0
fi

job=$(aws backup start-backup-job --region "$region" --backup-vault-name "$vault" --resource-arn "$arn" \
  --iam-role-arn "$role" --idempotency-token "$token" --lifecycle "DeleteAfterDays=$retention_days" \
  --recovery-point-tags "change=$label" --query BackupJobId --output text)
log started "\"job\":\"$job\""

elapsed=0
while :; do
  state=$(aws backup describe-backup-job --region "$region" --backup-job-id "$job" --query State --output text)
  case $state in
    COMPLETED) break ;;
    FAILED | ABORTED | EXPIRED) log failed "\"state\":\"$state\""; exit 1 ;;
  esac
  if ((elapsed >= wait)); then log timeout "\"state\":\"$state\""; exit 1; fi
  sleep "$poll"
  elapsed=$((elapsed + poll))
done

point=$(aws backup describe-backup-job --region "$region" --backup-job-id "$job" --query RecoveryPointArn --output text)
status=$(aws backup describe-recovery-point --region "$region" --backup-vault-name "$vault" --recovery-point-arn "$point" --query Status --output text)
[[ $status == COMPLETED ]] || { log not-available "\"status\":\"$status\""; exit 1; }
log available "\"recovery_point\":\"$point\""
