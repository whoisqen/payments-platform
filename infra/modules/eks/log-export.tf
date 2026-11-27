locals {
  log_export        = var.log_archive != null
  log_export_prefix = local.log_export ? "${trimsuffix(var.log_archive.prefix, "/")}/${local.name}/" : null
}

resource "aws_iam_role" "log_export_firehose" {
  count = local.log_export ? 1 : 0

  name                 = "${local.name}-log-export"
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "firehose.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "sts:ExternalId" = data.aws_caller_identity.current.account_id } }
    }]
  })
  tags = var.tags
}

data "aws_caller_identity" "current" {}

# The archive bucket encrypts with its own key by default; the key and bucket policies of log-archive admit roles named *-log-export.
resource "aws_iam_role_policy" "log_export_firehose" {
  count = local.log_export ? 1 : 0

  name = "write-log-archive"
  role = aws_iam_role.log_export_firehose[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetBucketLocation", "s3:ListBucket", "s3:ListBucketMultipartUploads"]
        Resource = var.log_archive.bucket_arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:AbortMultipartUpload"]
        Resource = "${var.log_archive.bucket_arn}/${trimsuffix(var.log_archive.prefix, "/")}/*"
      },
      {
        Effect    = "Allow"
        Action    = ["kms:GenerateDataKey", "kms:Encrypt"]
        Resource  = "arn:aws:kms:${var.region}:${var.log_archive.account_id}:key/*"
        Condition = { StringEquals = { "kms:ViaService" = "s3.${var.region}.amazonaws.com" } }
      },
    ]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "log_export" {
  count = local.log_export ? 1 : 0

  name        = "${local.name}-log-export"
  destination = "extended_s3"

  # Records at rest in the stream use the key of the control-plane log group.
  server_side_encryption {
    enabled  = true
    key_type = "CUSTOMER_MANAGED_CMK"
    key_arn  = var.logs_kms_key_arn
  }

  # CloudWatch Logs already gzips each record, so Firehose stores them as they come.
  extended_s3_configuration {
    role_arn            = aws_iam_role.log_export_firehose[0].arn
    bucket_arn          = var.log_archive.bucket_arn
    prefix              = local.log_export_prefix
    error_output_prefix = "${local.log_export_prefix}errors/!{firehose:error-output-type}/"
    buffering_size      = 64
    buffering_interval  = 300
    compression_format  = "UNCOMPRESSED"
  }

  tags = var.tags
}

resource "aws_iam_role" "log_export_logs" {
  count = local.log_export ? 1 : 0

  name                 = "${local.name}-log-subscription"
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringLike = { "aws:SourceArn" = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*" } }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "log_export_logs" {
  count = local.log_export ? 1 : 0

  name = "put-firehose"
  role = aws_iam_role.log_export_logs[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["firehose:PutRecord", "firehose:PutRecordBatch"]
      Resource = aws_kinesis_firehose_delivery_stream.log_export[0].arn
    }]
  })
}

resource "aws_cloudwatch_log_subscription_filter" "log_export" {
  count = local.log_export ? 1 : 0

  name            = "log-archive"
  log_group_name  = aws_cloudwatch_log_group.cluster.name
  filter_pattern  = ""
  destination_arn = aws_kinesis_firehose_delivery_stream.log_export[0].arn
  role_arn        = aws_iam_role.log_export_logs[0].arn

  depends_on = [aws_iam_role_policy.log_export_logs]
}
