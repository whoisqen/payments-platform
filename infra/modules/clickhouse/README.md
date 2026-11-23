# clickhouse

AWS side of self-managed ClickHouse: Pod Identity role and policy, backup settings and alarms. ClickHouse itself runs on EKS (section 5), so the cluster is a chart; this module has no EC2 or EKS resources.

- The `clickhouse-backup` CronJob runs hourly with zstd level 1 into the `s3-backup` bucket (35 days, Object Lock, D3, D4); the module outputs the schedule and compression for the chart.
- Restore loads the latest backup, then replays the event archive after it; the role reads only the archive prefix and cannot delete backups.
- `rpo_minutes <= 15` and `rto_hours <= 4` are validated; alarms on missing backups, restore time above 80% of the RTO and archive catch-up lag above the RPO.
- Jobs publish `BackupSuccess`, `backup_restore_duration_seconds` and `ArchiveCatchupLagSeconds` in `metric_namespace`.
- Buckets and keys are inputs; the bucket policy stays in the `s3-backup` module.
