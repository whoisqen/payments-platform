# BackupJobFailed

Layer backup-dr, service aws-backup, severity critical, owner data-platform-oncall, failure mode `backup-dr-backup-job-failed`.
Dashboard: https://grafana.payments.internal/d/backup

## Symptom

AWS Backup reports a FAILED or EXPIRED job in the last hour.

## Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=BackupJobFailed`) runs the read-only step of SSM document `pay-runbook-backup-job-failed` and gathers metrics, events and sanitized logs.
2. Read the job status message in AWS Backup for the resource.
3. Check the backup role, the KMS grant and the vault lock.

## Actions

1. Start an on-demand backup after the fix with document step `start-backup`.
2. Confirm the next scheduled job succeeds.

Every action runs through GitHub Actions `runbook-actions` (`workflow_dispatch`, input `document=pay-runbook-backup-job-failed`), which is audited.

## Escalation

Escalate to the commander if a locker or payments database has no recovery point for 2 hours. Default chain: primary acknowledges within 5 min, the secondary is paged at 5 min and the incident commander at 15 min (section 20.6).

## SSM document

`pay-runbook-backup-job-failed`
