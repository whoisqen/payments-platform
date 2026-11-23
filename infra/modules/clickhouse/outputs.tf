output "role_arn" {
  description = "Role of the backup CronJob and the restore Job."
  value       = aws_iam_role.backup.arn
}

output "backup_settings" {
  description = "Values for the deploy chart: schedule, compression, destination and retention of clickhouse-backup."
  value = {
    schedule           = local.backup_cron
    compression_format = var.compression_format
    compression_level  = var.compression_level
    retention_days     = var.retention_days
    prefix             = var.backup_prefix
    archive_prefix     = var.archive_prefix
    metric_namespace   = var.metric_namespace
  }
}

output "recovery_objectives" {
  description = "RPO in minutes and RTO in hours the module enforces."
  value       = { rpo_minutes = var.rpo_minutes, rto_hours = var.rto_hours }
}

output "alarm_arns" {
  description = "ARNs of the backup age, restore duration and archive lag alarms."
  value = [
    aws_cloudwatch_metric_alarm.backup_age.arn,
    aws_cloudwatch_metric_alarm.restore_duration.arn,
    aws_cloudwatch_metric_alarm.archive_lag.arn,
  ]
}
