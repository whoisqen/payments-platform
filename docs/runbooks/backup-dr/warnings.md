# backup-dr: non-paging alerts

Each section is the runbook of one ticket or Slack alert; the alert annotation links to its anchor. A ticket is handled in working hours; if the condition persists past the stated escalation, the owner raises it to the on-call.

## backup-copy-failed

Alert `BackupCopyFailed`, severity warning, owner data-platform-oncall, dashboard https://grafana.payments.internal/d/backup.

### Symptom

A copy job to us-east-1 or the backup account failed.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=BackupCopyFailed`) runs the read-only step of SSM document `pay-runbook-backup-copy-failed`.
2. Read the copy job message: KMS replica key, vault policy or quota.

### Actions

1. Retry the copy after the fix.

### Escalation

Ticket to data-platform; page if two copies in a row fail.

### SSM document

`pay-runbook-backup-copy-failed`

## metrics-backup-stale

Alert `MetricsBackupStale`, severity warning, owner data-platform-oncall, dashboard https://grafana.payments.internal/d/backup.

### Symptom

The CronJob `vmbackup-<n>` of one vmstorage node of the central metrics store has not succeeded for 3 hours. If the volume of that node is lost now, the history since the last backup is lost.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=MetricsBackupStale`) runs the read-only step of SSM document `pay-runbook-metrics-backup-stale`.
2. Look at the last Job of the CronJob in the namespace `victoria-metrics`: a pod that stays Pending means the node of the vmstorage pod has no room (the job must run on that node because the volume is ReadWriteOnce); a failed pod shows the S3 or Pod Identity error in its log.
3. Check that the Pod Identity association of the service account `victoria-metrics/vmbackup` and the bucket `<prefix>-shared-services-<short>-vmbackup` exist.

### Actions

1. Run the Job by hand from the CronJob once the cause is removed.

### Escalation

Ticket to data-platform; page nobody, the metrics are not a store of record.

### SSM document

`pay-runbook-metrics-backup-stale`

## snapshot-copy-stale

Alert `SnapshotCopyStale`, severity warning, owner data-platform-oncall, dashboard https://grafana.payments.internal/d/backup.

### Symptom

The hourly snapshot copy to us-east-1 is late.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=SnapshotCopyStale`) runs the read-only step of SSM document `pay-runbook-snapshot-copy-stale`.
2. Check the copy jobs and the cross-region KMS replica key.

### Actions

1. Start the copy manually with `start-backup`.

### Escalation

Ticket to data-platform.

### SSM document

`pay-runbook-snapshot-copy-stale`

## restore-duration-near-target

Alert `RestoreDurationNearTarget`, severity warning, owner data-platform-oncall, dashboard https://grafana.payments.internal/d/backup.

### Symptom

The last restore test took more than 80% of the target for the store.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=RestoreDurationNearTarget`) runs the read-only step of SSM document `pay-runbook-restore-duration-near-target`.
2. Compare the duration with the data size trend on the backup dashboard.

### Actions

1. Raise the restore capacity or parallel streams; plan partitioning if the data grows.

### Escalation

Ticket to data-platform.

### SSM document

`pay-runbook-restore-duration-near-target`

## restore-too-slow

Alert `RestoreTooSlow`, severity warning, owner data-platform-oncall, dashboard https://grafana.payments.internal/d/backup.

### Symptom

The last restore test took longer than the target of the store.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=RestoreTooSlow`) runs the read-only step of SSM document `pay-runbook-restore-too-slow`.
2. Find the slow step (restore, warm-up, readiness) in the restore log.

### Actions

1. Fix the slow step; re-run the test and confirm.

### Escalation

Ticket to data-platform; reported to the owner of the RTO budget.

### SSM document

`pay-runbook-restore-too-slow`

## dynamo-db-global-table-lag-high

Alert `DynamoDbGlobalTableLagHigh`, severity warning, owner data-platform-oncall, dashboard https://grafana.payments.internal/d/dr-switch.

### Symptom

Replication of a Global Table replica is slow.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=DynamoDbGlobalTableLagHigh`) runs the read-only step of SSM document `pay-runbook-dynamo-db-global-table-lag-high`.
2. Check the write throttling of the table and the replica status.

### Actions

1. Raise the capacity of the replica; writes come only from Frankfurt.

### Escalation

Ticket to data-platform.

### SSM document

`pay-runbook-dynamo-db-global-table-lag-high`

## s3-replication-lag-high

Alert `S3ReplicationLagHigh`, severity warning, owner data-platform-oncall, dashboard https://grafana.payments.internal/d/dr-switch.

### Symptom

Replication Time Control latency of a bucket is above 900 seconds.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=S3ReplicationLagHigh`) runs the read-only step of SSM document `pay-runbook-s3-replication-lag-high`.
2. Check pending replication operations and the replication role.

### Actions

1. Fix the replication role or KMS grant; AWS support if the backlog is on their side.

### Escalation

Ticket to data-platform.

### SSM document

`pay-runbook-s3-replication-lag-high`

## restore-test-stale

Alert `RestoreTestStale`, severity warning, owner data-platform-oncall, dashboard https://grafana.payments.internal/d/backup.

### Symptom

The daily restore verification did not run for over two days.

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=RestoreTestStale`) runs the read-only step of SSM document `pay-runbook-restore-test-stale`.
2. Check the scheduler of the restore automation and its last execution.

### Actions

1. Fix the schedule and run the test manually.

### Escalation

Ticket to data-platform.

### SSM document

`pay-runbook-restore-test-stale`

## dr-switch-test-overdue

Alert `DrSwitchTestOverdue`, severity warning, owner data-platform-oncall, dashboard https://grafana.payments.internal/d/dr-switch.

### Symptom

The us-east-1 standby has no successful full switch test in the last 100 days (the test is quarterly).

### Diagnostics

1. Collect one report: GitHub Actions `runbook-diagnose` (`workflow_dispatch`, input `alert=DrSwitchTestOverdue`) runs the read-only step of SSM document `pay-runbook-dr-switch-test-overdue`.
2. Check the test calendar and the last test report in `docs/dr/`.

### Actions

1. Schedule the test in the next window; the test switches one cell to the overdue region.

### Escalation

Ticket to the DR owner; reported in the monthly review.

### SSM document

`pay-runbook-dr-switch-test-overdue`
