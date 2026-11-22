from common import a, gap

L = "backup-dr"
D = "data-platform"
BK = "backup"
DR = "dr-switch"


a(layer=L, group="backups", name="BackupJobFailed", sev="critical", team=D, svc="aws-backup", comp="aws-backup", dash=BK,
  expr="sum by (backup_vault) (increase(aws_backup_number_of_backup_jobs_failed_sum[1h]) + increase(aws_backup_number_of_backup_jobs_expired_sum[1h])) > 0", f="0m",
  sum="An AWS Backup job failed or expired",
  series=[('aws_backup_number_of_backup_jobs_failed_sum{backup_vault="gold"}', "0+1x{n}", "0+0x{n}"), ('aws_backup_number_of_backup_jobs_expired_sum{backup_vault="gold"}', "0+0x{n}", "0+0x{n}")],
  labels={"backup_vault": "gold"},
  failure="backup job failed or expired", impact="a store has no fresh recovery point; data loss on restore grows beyond the 5-minute target (D2) or the hourly target (D3)",
  sym="AWS Backup reports a FAILED or EXPIRED job in the last hour.",
  diag=["Read the job status message in AWS Backup for the resource.", "Check the backup role, the KMS grant and the vault lock."],
  act=["Start an on-demand backup after the fix with document step `start-backup`.", "Confirm the next scheduled job succeeds."],
  esc="Escalate to the commander if a locker or payments database has no recovery point for 2 hours.")

a(layer=L, group="backups", name="BackupMissing", sev="critical", team=D, svc="aws-backup", comp="aws-backup", dash=BK,
  expr="time() - max by (store) (backup_last_success_timestamp_seconds) > 2 * max by (store) (backup_interval_seconds)", f="5m",
  sum="The last successful backup of a store is older than twice its interval",
  series=[('backup_last_success_timestamp_seconds{store="memorydb-cell-1"}', "0x{n}", "0+60x{n}"), ('backup_interval_seconds{store="memorydb-cell-1"}', "300x{n}", "300x{n}")],
  failure="backup missing", impact="the recovery point is older than the allowed loss",
  sym="No successful backup of the store within two intervals.",
  diag=["Check the backup plan schedule and the last job of the resource."],
  act=["Run an on-demand backup with `start-backup`; check that the plan still selects the resource by tag."],
  esc="Escalate to the commander for payment databases.")

a(layer=L, group="backups", name="BackupCopyFailed", sev="warning", team=D, svc="aws-backup", comp="aws-backup", dash=BK,
  expr="sum by (backup_vault) (increase(aws_backup_number_of_copy_jobs_failed_sum[1h])) > 0", f="0m",
  sum="A backup copy to a recovery region or to the backup account failed",
  series=[('aws_backup_number_of_copy_jobs_failed_sum{backup_vault="gold"}', "0+1x{n}", "0+0x{n}")], labels={"backup_vault": "gold"},
  failure="backup copy failed", impact="a recovery region lacks the latest hourly copy",
  sym="A copy job to us-east-1, us-east-2 or the backup account failed.",
  diag=["Read the copy job message: KMS replica key, vault policy or quota."],
  act=["Retry the copy after the fix."],
  esc="Ticket to data-platform; page if two copies in a row fail.")

a(layer=L, group="backups", name="SnapshotCopyStale", sev="warning", team=D, svc="aws-backup", comp="snapshot-copy", dash=BK,
  expr="time() - max by (store, region) (snapshot_copy_last_success_timestamp_seconds) > 2 * 3600", f="5m", T=130,
  sum="The latest snapshot copy in a recovery region is older than 2 hours",
  series=[('snapshot_copy_last_success_timestamp_seconds{store="memorydb-cell-1",region="us-east-2"}', "0x{n}", "0+60x{n}")],
  failure="snapshot copy stale in a recovery region", impact="the snapshot-only stores (MemoryDB, ClickHouse, Vault, Velero) lose more than the 1 h target at a switch",
  sym="The hourly snapshot copy to us-east-1 or us-east-2 is late.",
  diag=["Check the copy jobs and the cross-region KMS replica key."],
  act=["Start the copy manually with `start-backup`."],
  esc="Ticket to data-platform.")

a(layer=L, group="restore", name="RestoreTestFailed", sev="critical", team=D, svc="restore-verifier", comp="restore-test", dash=BK,
  expr="min by (store) (restore_test_success) == 0", f="5m",
  sum="The automatic restore test of a store failed",
  series=[('restore_test_success{store="aurora-cell-1"}', "0x{n}", "1x{n}")],
  failure="restore test failed", impact="a backup that cannot be restored is not a backup; D2 and D4 targets are unproven",
  sym="The daily automatic restore into the scratch environment failed or its data check did not pass.",
  diag=["Read the restore automation log: restore, warm-up (pg_prewarm), row-count and checksum steps.", "Check quotas and KMS access of the restore role."],
  act=["Fix the cause and rerun the document `pay-runbook-restore-test-failed` for the store.", "Until it passes, take an extra on-demand backup and keep the previous passing one."],
  esc="Escalate to the commander if the production restore path itself is broken.")

a(layer=L, group="restore", name="RestoreDurationNearTarget", sev="warning", team=D, svc="restore-verifier", comp="restore-test", dash=BK,
  expr="max by (store) (backup_restore_duration_seconds) > 0.8 * max by (store) (backup_restore_target_seconds)", f="0m",
  sum="Restore duration passed 80% of its target",
  series=[('backup_restore_duration_seconds{store="aurora-cell-1"}', "1500x{n}", "600x{n}"), ('backup_restore_target_seconds{store="aurora-cell-1"}', "1800x{n}", "1800x{n}")],
  failure="restore close to its target", impact="the 30-minute restore target (D4) will be missed as data grows",
  sym="The last restore test took more than 80% of the target for the store.",
  diag=["Compare the duration with the data size trend on the backup dashboard."],
  act=["Raise the restore capacity or parallel streams; plan partitioning if the data grows."],
  esc="Ticket to data-platform.")

a(layer=L, group="restore", name="RestoreTooSlow", sev="warning", team=D, svc="restore-verifier", comp="restore-test", dash=BK,
  expr="max by (store) (backup_restore_duration_seconds) > max by (store) (backup_restore_target_seconds)", f="0m",
  sum="Restore duration exceeded its target",
  series=[('backup_restore_duration_seconds{store="aurora-cell-1"}', "2000x{n}", "1500x{n}"), ('backup_restore_target_seconds{store="aurora-cell-1"}', "1800x{n}", "1800x{n}")],
  failure="restore slower than target", impact="the RTO of the store is not met",
  sym="The last restore test took longer than the target of the store.",
  diag=["Find the slow step (restore, warm-up, readiness) in the restore log."],
  act=["Fix the slow step; re-run the test and confirm."],
  esc="Ticket to data-platform; reported to the owner of the RTO budget.")

a(layer=L, group="replication", name="LatestRestorableTimeLagHigh", sev="critical", team=D, svc="aurora", comp="pitr", dash=BK,
  expr="max by (store) (database_latest_restorable_time_lag_seconds) > 300", f="10m",
  sum="The latest restorable time of a database lags more than 5 minutes",
  series=[('database_latest_restorable_time_lag_seconds{store="aurora-cell-1"}', "600x{n}", "30x{n}")],
  failure="latest restorable time lags", impact="a point-in-time restore would lose more than the 5-minute target (D2)",
  sym="The latest restorable time of an Aurora cluster or a DynamoDB table is more than 5 minutes behind now for 10 minutes.",
  diag=["Check the cluster events and the continuous backup status of the resource.", "Check whether a writer failover or maintenance interrupted the log shipping."],
  act=["If continuous backup is off, restore the setting through Terraform.", "Open an AWS support case if the status is healthy but the lag stays."],
  esc="Escalate to the commander when the lag exceeds 30 minutes.")

a(layer=L, group="replication", name="AuroraGlobalLagHigh", sev="critical", team=D, svc="aurora", comp="global-database", dash=DR,
  expr="max by (global_cluster, region) (aws_rds_aurora_global_db_replication_lag_maximum) > 5000", f="2m",
  sum="Aurora Global Database lag above 5 seconds",
  series=[('aws_rds_aurora_global_db_replication_lag_maximum{global_cluster="payments-cell-1",region="us-east-1"}', "6000x{n}", "800x{n}")],
  failure="Aurora Global lag above 5 s", impact="the 10 s RPO budget (D7) is at risk; managed RPO stays off so the writer is not paused",
  sym="The replication lag to a headless secondary in us-east-1 or us-east-2 exceeds 5 s (the metric is in milliseconds).",
  diag=["Check the write rate of the cluster and the cross-region network.", "Check the lag per secondary region to see whether one link is slow."],
  act=["Reduce heavy batch writes (migrations, backfills) with document step `pause-batch`.", "Do not enable `rds.global_db_rpo`: it pauses commits in Frankfurt."],
  esc="Escalate when the lag passes 10 s: see `aurora-global-lag-rpo-budget-exceeded`.")

a(layer=L, group="replication", name="AuroraGlobalLagRpoBudgetExceeded", sev="critical", team=D, svc="aurora", comp="global-database", dash=DR,
  expr="max by (global_cluster, region) (aws_rds_aurora_global_db_replication_lag_maximum) > 10000", f="1m",
  sum="Aurora Global Database lag above the 10 second RPO budget",
  series=[('aws_rds_aurora_global_db_replication_lag_maximum{global_cluster="payments-cell-1",region="us-east-1"}', "12000x{n}", "6000x{n}")],
  failure="Aurora Global lag above the RPO budget", impact="a switch now would lose more than 10 s of payment data; reconciliation covers the gap",
  sym="The lag to a recovery region is above the 10 s RPO budget.",
  diag=["Follow the diagnostics of `aurora-global-lag-high`."],
  act=["Pause batch writes; if the secondary link is broken, ask AWS support and record the exposure window for the reconciliation."],
  esc="Inform the commander: the exposure window must be recorded for the PSP reconciliation.")

a(layer=L, group="replication", name="DynamoDbGlobalTableLagHigh", sev="warning", team=D, svc="dynamodb", comp="global-tables", dash=DR,
  expr="max by (table_name, receiving_region) (aws_dynamodb_replication_latency_maximum) > 5000", f="10m",
  sum="DynamoDB Global Table replication latency above 5 seconds",
  series=[('aws_dynamodb_replication_latency_maximum{table_name="merchant-cell-map",receiving_region="us-east-2"}', "9000x{n}", "500x{n}")],
  failure="Global Table replication lag", impact="the merchant-to-cell map in a recovery region is behind (RPO is seconds)",
  sym="Replication of a Global Table replica is slow.",
  diag=["Check the write throttling of the table and the replica status."],
  act=["Raise the capacity of the replica; writes come only from Frankfurt."],
  esc="Ticket to data-platform.")

a(layer=L, group="replication", name="S3ReplicationLagHigh", sev="warning", team=D, svc="s3", comp="s3-replication", dash=DR,
  expr="max by (bucket, destination_region) (aws_s3_replication_latency_maximum) > 900", f="10m",
  sum="S3 replication latency above the 15 minute RTC target",
  series=[('aws_s3_replication_latency_maximum{bucket="pay-backups",destination_region="us-east-1"}', "1500x{n}", "120x{n}")],
  failure="S3 replication lag", impact="the S3 and event-archive RPO of 15 min is exceeded",
  sym="Replication Time Control latency of a bucket is above 900 seconds.",
  diag=["Check pending replication operations and the replication role."],
  act=["Fix the replication role or KMS grant; AWS support if the backlog is on their side."],
  esc="Ticket to data-platform.")

a(layer=L, group="drills", name="RestoreTestStale", sev="warning", team=D, svc="restore-verifier", comp="restore-test", dash=BK,
  expr="time() - max by (store) (restore_test_last_run_timestamp_seconds) > 2 * 86400", f="0m", eval_interval="1d",
  sum="No automatic restore test ran for a store in 2 days",
  series=[('restore_test_last_run_timestamp_seconds{store="aurora-cell-1"}', "0", "0")], labels={"store": "aurora-cell-1"}, skip_auto=True,
  extra_tests=[
      {"interval": "1d", "input_series": [{"series": 'restore_test_last_run_timestamp_seconds{store="aurora-cell-1"}', "values": "0x10"}],
       "alert_rule_test": [{"eval_time": "5d", "alertname": "RestoreTestStale", "exp_alerts": [{"exp_labels": {"severity": "warning", "team": D, "service": "restore-verifier", "owner": f"{D}-oncall", "layer": L, "failure_mode": "backup-dr-restore-test-stale", "store": "aurora-cell-1"}, "exp_annotations": {"summary": "No automatic restore test ran for a store in 2 days", "runbook_url": "https://github.com/whoisqen/payments-platform/blob/main/docs/runbooks/backup-dr/warnings.md#restore-test-stale", "dashboard_url": "https://grafana.payments.internal/d/backup"}}]}]},
      {"interval": "1d", "input_series": [{"series": 'restore_test_last_run_timestamp_seconds{store="aurora-cell-1"}', "values": "0+86400x10"}],
       "alert_rule_test": [{"eval_time": "5d", "alertname": "RestoreTestStale", "exp_alerts": []}]}],
  failure="restore test not running", impact="the daily verification of D2 is silent",
  sym="The daily restore verification did not run for over two days.",
  diag=["Check the scheduler of the restore automation and its last execution."],
  act=["Fix the schedule and run the test manually."],
  esc="Ticket to data-platform.")

a(layer=L, group="drills", name="DrSwitchTestOverdue", sev="warning", team=D, svc="dr-switch", comp="dr-test", dash=DR,
  expr="time() - max by (region) (dr_switch_test_last_success_timestamp_seconds) > 100 * 86400", f="0m", eval_interval="1d",
  sum="The quarterly switch test of a recovery region is overdue",
  series=[('dr_switch_test_last_success_timestamp_seconds{region="us-east-1"}', "0", "0")], labels={"region": "us-east-1"}, skip_auto=True,
  extra_tests=[
      {"interval": "1d", "input_series": [{"series": 'dr_switch_test_last_success_timestamp_seconds{region="us-east-1"}', "values": "0x110"}, {"series": 'dr_switch_test_last_success_timestamp_seconds{region="us-east-2"}', "values": "0+86400x110"}],
       "alert_rule_test": [{"eval_time": "101d", "alertname": "DrSwitchTestOverdue", "exp_alerts": [{"exp_labels": {"severity": "warning", "team": D, "service": "dr-switch", "owner": f"{D}-oncall", "layer": L, "failure_mode": "backup-dr-dr-switch-test-overdue", "region": "us-east-1"}, "exp_annotations": {"summary": "The quarterly switch test of a recovery region is overdue", "runbook_url": "https://github.com/whoisqen/payments-platform/blob/main/docs/runbooks/backup-dr/warnings.md#dr-switch-test-overdue", "dashboard_url": "https://grafana.payments.internal/d/dr-switch"}}]}]},
      {"interval": "1d", "input_series": [{"series": 'dr_switch_test_last_success_timestamp_seconds{region="us-east-1"}', "values": "0+86400x110"}, {"series": 'dr_switch_test_last_success_timestamp_seconds{region="us-east-2"}', "values": "0+86400x110"}],
       "alert_rule_test": [{"eval_time": "101d", "alertname": "DrSwitchTestOverdue", "exp_alerts": []}]}],
  failure="quarterly switch test overdue", impact="the 60 min RTO (75 min in plan B) is not measured; the switch runbook may have rotted",
  sym="A recovery region has no successful full switch test in the last 100 days (the test is quarterly, to us-east-1 and us-east-2 in turn).",
  diag=["Check the test calendar and the last test report in `docs/dr/`."],
  act=["Schedule the test in the next window; the test switches one cell to the overdue region."],
  esc="Ticket to the DR owner; reported in the monthly review.")

a(layer=L, group="detection", name="BackupVaultPolicyChanged", sev="security", team="security", svc="aws-backup", comp="backup-vault", dash=BK,
  expr='sum(increase(security_events_total{event="backup_vault_policy_change"}[10m])) > 0', f="0m",
  sum="A backup vault access policy or lock changed",
  series=[('security_events_total{event="backup_vault_policy_change"}', "0+1x{n}", "0+0x{n}")], labels={},
  failure="backup vault policy changed", impact="backups could be deleted or exposed; PCI DSS 3.6 and ransomware protection",
  sym="EventBridge recorded a change of a backup vault policy or Vault Lock.",
  diag=["Compare the change with the Atlantis apply of an approved pull request."],
  act=["If unapproved, revert from Git with the audited workflow and revoke the actor's session."],
  esc="Open a security incident if the actor is not the automation role.")

gap(L, "recovery-region-quota-low", "recovery-regions", "Service quotas in us-east-1 or us-east-2 below the switch plan", "compute cannot be created at the switch (plan B trigger)", "warning", "quota metrics of the recovery regions are not collected yet")
