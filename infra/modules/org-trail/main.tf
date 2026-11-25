locals {
  name           = "${var.name_prefix}-${var.env}-${var.region_short}-${var.component}"
  trail_arn      = "arn:aws:cloudtrail:${var.region_name}:${var.account_id}:trail/${local.name}"
  log_group_name = "/aws/cloudtrail/${local.name}"
  log_group_arn  = "arn:aws:logs:${var.region_name}:${var.account_id}:log-group:${local.log_group_name}"

  logs_key_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "CloudWatchLogs"
        Effect    = "Allow"
        Principal = { Service = "logs.${var.region_name}.amazonaws.com" }
        Action    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        Resource  = "*"
        Condition = { ArnEquals = { "kms:EncryptionContext:aws:logs:arn" = local.log_group_arn } }
      },
    ]
  }

  cloudwatch_role_policy = {
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DeliverToLogGroup"
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${local.log_group_arn}:log-stream:*"
    }]
  }

  cde_object_arns = [for p in var.cde_s3_bucket_prefixes : "arn:aws:s3:::${p}"]
}

resource "aws_kms_key" "logs" {
  description             = "Encrypts the CloudWatch Logs copy of ${local.name}."
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days
  policy                  = jsonencode(local.logs_key_policy)

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "this" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.logs.arn

  tags = var.tags
}

resource "aws_iam_role" "cloudwatch" {
  name = "${local.name}-cloudwatch"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceArn" = local.trail_arn } }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "cloudwatch" {
  name   = "deliver-to-log-group"
  role   = aws_iam_role.cloudwatch.id
  policy = jsonencode(local.cloudwatch_role_policy)
}

resource "aws_cloudtrail" "this" {
  name                          = local.name
  is_organization_trail         = true
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  s3_bucket_name                = var.s3_bucket_name
  s3_key_prefix                 = var.s3_key_prefix
  kms_key_id                    = var.s3_kms_key_arn
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.this.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudwatch.arn

  advanced_event_selector {
    name = "management-events"

    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }

  advanced_event_selector {
    name = "cde-s3-data-events"

    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }

    field_selector {
      field  = "resources.type"
      equals = ["AWS::S3::Object"]
    }

    field_selector {
      field       = "resources.ARN"
      starts_with = local.cde_object_arns
    }
  }

  tags = var.tags

  depends_on = [aws_iam_role_policy.cloudwatch]
}
