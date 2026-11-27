#!/usr/bin/env bash
# Starts one SSM Automation execution of a runbook document and waits for it; only step names and statuses reach the log.
# Usage: ssm-run.sh [--dry-run] <request.json>   (request.json: the output of runbook.py)
set -euo pipefail

dry_run=false
if [ "${1:-}" = --dry-run ]; then dry_run=true; shift; fi
request=${1:?usage: ssm-run.sh [--dry-run] <request.json>}
timeout_s=${RUNBOOK_TIMEOUT_SECONDS:-1800}

doc=$(jq -r .document "$request")
mode=$(jq -r .mode "$request")
step=$(jq -r .step "$request")
region=$(jq -r .region "$request")
exec_role=$(jq -r .execution_role "$request")
[[ $doc =~ ^pay-runbook-[a-z0-9-]+$ && $mode =~ ^(diagnose|act)$ && $step =~ ^[a-z0-9-]*$ ]] || { echo "::error::bad request"; exit 1; }

# the execution role, not the caller, decides what the document may change: diagnose passes the read-only role
params=$(jq -nc --arg m "$mode" --arg s "$step" --arg r "$exec_role" \
  '{Mode: [$m], AutomationAssumeRole: [$r]} + (if $s == "" then {} else {Step: [$s]} end)')
summary=${GITHUB_STEP_SUMMARY:-/dev/stdout}

if [ "$dry_run" = true ]; then
  echo "dry run: aws ssm start-automation-execution --region ${region} --document-name ${doc} --parameters ${params}"
  exit 0
fi

aws ssm describe-document --region "$region" --name "$doc" --query 'Document.DocumentType' --output text | grep -qx Automation ||
  { echo "::error::${doc} is not an Automation document in ${region}"; exit 1; }
id=$(aws ssm start-automation-execution --region "$region" --document-name "$doc" --parameters "$params" \
  --tags "Key=github-run,Value=${GITHUB_RUN_ID:-local}" --query AutomationExecutionId --output text)
echo "execution ${id} of ${doc} (${mode}${step:+, step ${step}}) in ${region}"

deadline=$((SECONDS + timeout_s))
while :; do
  status=$(aws ssm get-automation-execution --region "$region" --automation-execution-id "$id" \
    --query AutomationExecution.AutomationExecutionStatus --output text)
  case "$status" in
    Success | Failed | TimedOut | Cancelled | CompletedWithFailure | CompletedWithSuccess | Rejected) break ;;
  esac
  if [ "$SECONDS" -ge "$deadline" ]; then
    aws ssm stop-automation-execution --region "$region" --automation-execution-id "$id" >/dev/null
    echo "::error::${id} did not finish in ${timeout_s}s and was stopped"; exit 1
  fi
  sleep 10
done

# outputs and logs may carry sensitive data, so only the report location the document publishes is shown
exec_json=$(aws ssm get-automation-execution --region "$region" --automation-execution-id "$id" --output json)
{
  echo "### ${doc}: ${status}"
  echo
  echo "| step | status |"
  echo "|---|---|"
  jq -r '.AutomationExecution.StepExecutions[] | "| \(.StepName) | \(.StepStatus) |"' <<<"$exec_json"
  report=$(jq -r '.AutomationExecution.Outputs["ReportUri"][0] // empty' <<<"$exec_json")
  [ -n "$report" ] && echo && echo "Report: \`${report}\`"
  true
} >>"$summary"
[ "$status" = Success ] || [ "$status" = CompletedWithSuccess ] || { echo "::error::${id} ended ${status}"; exit 1; }
