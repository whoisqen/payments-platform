# restore-automation

SSM Automation document and EventBridge trigger for the daily restore test (D2, D4); the plans themselves are in `modules/backup`.
A finished Aurora or DynamoDB restore job starts the document: optional validator Lambda, then CloudWatch metrics
`RestoreDurationSeconds`, `RestoreTargetSeconds` (default 1800) and `RestoreSuccess` per store in `metric_namespace`.
The exporter maps them to `backup_restore_*`; alerts are in `observability/alerts/backup-dr/restore.yaml`.
Test: `terraform init -backend=false && terraform test`.
