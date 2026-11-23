mock_provider "aws" {}

variables {
  name_prefix         = "pay"
  env                 = "prod"
  region_short        = "euc1"
  cluster_name        = "pay-prod-euc1-platform"
  kms_key_arn         = "arn:aws:kms:eu-central-1:111111111111:key/mrk-0001"
  backup_bucket_arn   = "arn:aws:s3:::pay-prod-euc1-backup"
  archive_bucket_arn  = "arn:aws:s3:::pay-prod-euc1-event-archive"
  archive_kms_key_arn = "arn:aws:kms:eu-central-1:111111111111:key/mrk-0002"

  tags = {
    team          = "data"
    owner         = "data@example.com"
    "pci-scope"   = "connected"
    "data-class"  = "internal"
    "backup-tier" = "silver"
  }
}

run "hourly_zstd_backup_with_recovery_objectives" {
  command = plan

  assert {
    condition     = output.backup_settings.schedule == "0 * * * *" && output.backup_settings.compression_format == "zstd" && output.backup_settings.compression_level == 1 && output.backup_settings.retention_days == 35
    error_message = "hourly zstd low-level backup kept 35 days"
  }

  assert {
    condition     = output.recovery_objectives.rpo_minutes == 15 && output.recovery_objectives.rto_hours == 4
    error_message = "RPO 15 minutes and RTO 4 hours"
  }

  assert {
    condition     = aws_iam_role.backup.name == "pay-prod-euc1-clickhouse-backup" && aws_eks_pod_identity_association.backup.service_account == "clickhouse-backup"
    error_message = "standard name and Pod Identity association"
  }
}

run "alarms_follow_the_objectives" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.backup_age.period == 3600 && aws_cloudwatch_metric_alarm.backup_age.evaluation_periods == 2 && aws_cloudwatch_metric_alarm.backup_age.treat_missing_data == "breaching"
    error_message = "backup age alarm after two missed hourly backups"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.restore_duration.threshold == 11520 && aws_cloudwatch_metric_alarm.archive_lag.threshold == 900
    error_message = "restore alarm at 80% of 4 hours and lag alarm at the 15 minute RPO"
  }
}

run "policy_is_least_privilege" {
  command = plan

  assert {
    condition     = !strcontains(aws_iam_role_policy.backup.policy, "s3:DeleteObject") && !strcontains(aws_iam_role_policy.backup.policy, "s3:*") && !strcontains(aws_iam_role_policy.backup.policy, "kms:*")
    error_message = "no delete and no wildcard actions"
  }

  assert {
    condition     = strcontains(aws_iam_role_policy.backup.policy, "pay-prod-euc1-event-archive/events/*") && strcontains(aws_iam_role_policy.backup.policy, "pay-prod-euc1-backup/backups/clickhouse/*")
    error_message = "access limited to the backup and archive prefixes"
  }
}

run "rpo_above_15_minutes_is_rejected" {
  command = plan

  variables {
    rpo_minutes = 30
  }

  expect_failures = [var.rpo_minutes]
}

run "rto_above_4_hours_is_rejected" {
  command = plan

  variables {
    rto_hours = 6
  }

  expect_failures = [var.rto_hours]
}

run "backup_less_often_than_hourly_is_rejected" {
  command = plan

  variables {
    backup_interval_minutes = 120
  }

  expect_failures = [var.backup_interval_minutes]
}

run "only_low_level_zstd_is_accepted" {
  command = plan

  variables {
    compression_level = 12
  }

  expect_failures = [var.compression_level]
}

run "other_compression_is_rejected" {
  command = plan

  variables {
    compression_format = "gzip"
  }

  expect_failures = [var.compression_format]
}

run "tag_schema_is_enforced" {
  command = plan

  variables {
    tags = { team = "data" }
  }

  expect_failures = [var.tags]
}
