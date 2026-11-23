locals {
  name = "${var.name_prefix}-${var.env}-${var.region_short}-${var.component}"

  backup_cron = var.backup_interval_minutes == 60 ? "0 * * * *" : "*/${var.backup_interval_minutes} * * * *"

  restore_alarm_seconds = var.rto_hours * 3600 * 0.8
}

resource "aws_iam_role" "backup" {
  name = "${local.name}-backup"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = var.tags
}

# Self-managed ClickHouse runs on EKS (section 5), so the backup pods get this role through Pod Identity.
resource "aws_eks_pod_identity_association" "backup" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.backup.arn

  tags = var.tags
}

locals {
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListBackupPrefix"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:ListBucketMultipartUploads"]
        Resource = [var.backup_bucket_arn]
        Condition = {
          StringLike = { "s3:prefix" = ["${var.backup_prefix}*"] }
        }
      },
      # No delete: the bucket lifecycle expires backups and Object Lock keeps them until then.
      {
        Sid      = "WriteReadBackups"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
        Resource = ["${var.backup_bucket_arn}/${var.backup_prefix}*"]
      },
      {
        Sid      = "ListArchivePrefix"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [var.archive_bucket_arn]
        Condition = {
          StringLike = { "s3:prefix" = ["${var.archive_prefix}*"] }
        }
      },
      {
        Sid      = "ReadEventArchive"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${var.archive_bucket_arn}/${var.archive_prefix}*"]
      },
      {
        Sid      = "BackupKey"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = [var.kms_key_arn]
      },
      {
        Sid      = "ArchiveKey"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [var.archive_kms_key_arn]
      },
      # PutMetricData has no resource-level permissions, so the namespace condition is the scope.
      {
        Sid       = "PublishJobMetrics"
        Effect    = "Allow"
        Action    = ["cloudwatch:PutMetricData"]
        Resource  = ["*"]
        Condition = { StringEquals = { "cloudwatch:namespace" = var.metric_namespace } }
      },
    ]
  })
}

resource "aws_iam_role_policy" "backup" {
  name   = "backup-and-restore"
  role   = aws_iam_role.backup.id
  policy = local.policy
}

# The CronJob publishes BackupSuccess after each upload; a missing datapoint counts as a failure.
resource "aws_cloudwatch_metric_alarm" "backup_age" {
  alarm_name          = "${local.name}-backup-age"
  alarm_description   = "No successful ClickHouse backup for ${var.max_missed_backups} intervals"
  namespace           = var.metric_namespace
  metric_name         = "BackupSuccess"
  statistic           = "Sum"
  period              = var.backup_interval_minutes * 60
  evaluation_periods  = var.max_missed_backups
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = var.alarm_actions

  dimensions = {
    Cluster = local.name
  }

  tags = var.tags
}

# D4: alert at 80% of the RTO budget.
resource "aws_cloudwatch_metric_alarm" "restore_duration" {
  alarm_name          = "${local.name}-restore-duration"
  alarm_description   = "backup_restore_duration_seconds above 80% of the ${var.rto_hours} hour RTO"
  namespace           = var.metric_namespace
  metric_name         = "backup_restore_duration_seconds"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = local.restore_alarm_seconds
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions

  dimensions = {
    Cluster = local.name
  }

  tags = var.tags
}

# Lag of the insert path behind the event archive; above the RPO the catch-up window is not covered.
resource "aws_cloudwatch_metric_alarm" "archive_lag" {
  alarm_name          = "${local.name}-archive-catchup-lag"
  alarm_description   = "Event archive catch-up lag above the ${var.rpo_minutes} minute RPO"
  namespace           = var.metric_namespace
  metric_name         = "ArchiveCatchupLagSeconds"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.rpo_minutes * 60
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = var.alarm_actions

  dimensions = {
    Cluster = local.name
  }

  tags = var.tags
}
