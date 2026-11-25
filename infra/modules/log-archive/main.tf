locals {
  name        = "${var.name_prefix}-${var.env}-${var.region_short}-${var.component}"
  bucket_arn  = "arn:aws:s3:::${local.name}"
  access_name = "${local.name}-access-logs"
  access_arn  = "arn:aws:s3:::${local.access_name}"
  org_source  = { StringEquals = { "aws:SourceOrgID" = var.organization_id } }

  tls_only = {
    Sid       = "DenyInsecureTransport"
    Effect    = "Deny"
    Principal = "*"
    Action    = "s3:*"
    Condition = { Bool = { "aws:SecureTransport" = "false" } }
  }

  readers = length(var.reader_principal_arns) > 0 ? [{
    Sid       = "AllowAuditReaders"
    Effect    = "Allow"
    Principal = { AWS = var.reader_principal_arns }
    Action    = ["s3:GetObject", "s3:GetObjectVersion", "s3:ListBucket", "s3:GetBucketLocation"]
    Resource  = [local.bucket_arn, "${local.bucket_arn}/*"]
  }] : []

  bucket_policy = {
    Version = "2012-10-17"
    Statement = concat([
      merge(local.tls_only, { Resource = [local.bucket_arn, "${local.bucket_arn}/*"] }),
      {
        # Object Lock already blocks deletes of locked versions; this also covers delete markers and the bucket.
        Sid       = "DenyDelete"
        Effect    = "Deny"
        Principal = "*"
        Action    = ["s3:DeleteBucket", "s3:DeleteObject", "s3:DeleteObjectVersion", "s3:BypassGovernanceRetention"]
        Resource  = [local.bucket_arn, "${local.bucket_arn}/*"]
      },
      {
        Sid       = "CloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = local.bucket_arn
        Condition = { StringEquals = { "aws:SourceArn" = var.trail_arn } }
      },
      {
        Sid       = "CloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource = [
          "${local.bucket_arn}/${var.prefixes.cloudtrail}/AWSLogs/${var.management_account_id}/*",
          "${local.bucket_arn}/${var.prefixes.cloudtrail}/AWSLogs/${var.organization_id}/*",
        ]
        Condition = { StringEquals = { "aws:SourceArn" = var.trail_arn, "s3:x-amz-acl" = "bucket-owner-full-control" } }
      },
      {
        Sid       = "ConfigAclCheck"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = ["s3:GetBucketAcl", "s3:ListBucket"]
        Resource  = local.bucket_arn
        Condition = local.org_source
      },
      {
        Sid       = "ConfigWrite"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${local.bucket_arn}/${var.prefixes.config}/AWSLogs/*/Config/*"
        Condition = { StringEquals = { "aws:SourceOrgID" = var.organization_id, "s3:x-amz-acl" = "bucket-owner-full-control" } }
      },
      {
        Sid       = "FlowLogsAclCheck"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = local.bucket_arn
        Condition = local.org_source
      },
      {
        Sid       = "FlowLogsWrite"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${local.bucket_arn}/${var.prefixes.flow_logs}/AWSLogs/*"
        Condition = { StringEquals = { "aws:SourceOrgID" = var.organization_id, "s3:x-amz-acl" = "bucket-owner-full-control" } }
      },
    ], local.readers)
  }

  access_policy = {
    Version = "2012-10-17"
    Statement = [
      merge(local.tls_only, { Resource = [local.access_arn, "${local.access_arn}/*"] }),
      {
        Sid       = "S3ServerAccessLogs"
        Effect    = "Allow"
        Principal = { Service = "logging.s3.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${local.access_arn}/*"
        Condition = {
          StringEquals = { "aws:SourceAccount" = var.account_id }
          ArnLike      = { "aws:SourceArn" = local.bucket_arn }
        }
      },
    ]
  }

  key_policy = {
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid       = "AccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "CloudTrailEncrypt"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "kms:GenerateDataKey*"
        Resource  = "*"
        Condition = {
          StringEquals = { "aws:SourceArn" = var.trail_arn }
          StringLike   = { "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:aws:cloudtrail:*:${var.management_account_id}:trail/*" }
        }
      },
      {
        Sid       = "CloudTrailDescribe"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "kms:DescribeKey"
        Resource  = "*"
        Condition = { StringEquals = { "aws:SourceArn" = var.trail_arn } }
      },
      {
        Sid       = "ConfigAndFlowLogsEncrypt"
        Effect    = "Allow"
        Principal = { Service = ["config.amazonaws.com", "delivery.logs.amazonaws.com"] }
        Action    = ["kms:GenerateDataKey*", "kms:Encrypt", "kms:Decrypt", "kms:DescribeKey"]
        Resource  = "*"
        Condition = local.org_source
      },
      ], length(var.reader_principal_arns) > 0 ? [{
        Sid       = "AuditReadersDecrypt"
        Effect    = "Allow"
        Principal = { AWS = var.reader_principal_arns }
        Action    = ["kms:Decrypt", "kms:DescribeKey"]
        Resource  = "*"
    }] : [])
  }
}

resource "aws_kms_key" "this" {
  description             = "Encrypts the organization trail, Config and VPC Flow Logs in ${local.name}."
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days
  policy                  = jsonencode(local.key_policy)

  tags = var.tags
}

resource "aws_kms_alias" "this" {
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.this.key_id
}

resource "aws_s3_bucket" "this" {
  bucket              = local.name
  object_lock_enabled = true

  tags = var.tags
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = var.object_lock_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.this.arn
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "archive-then-expire"
    status = "Enabled"

    filter {}

    transition {
      days          = var.glacier_after_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.expiration_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_logging" "this" {
  bucket        = aws_s3_bucket.this.id
  target_bucket = aws_s3_bucket.access.id
  target_prefix = "${local.name}/"

  target_object_key_format {
    partitioned_prefix {
      partition_date_source = "EventTime"
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = jsonencode(local.bucket_policy)

  depends_on = [aws_s3_bucket_public_access_block.this]
}

# Server access logs cannot target a bucket with default Object Lock retention or SSE-KMS, so they get their own bucket.
resource "aws_s3_bucket" "access" {
  bucket = local.access_name

  tags = var.tags
}

resource "aws_s3_bucket_ownership_controls" "access" {
  bucket = aws_s3_bucket.access.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "access" {
  bucket = aws_s3_bucket.access.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "access" {
  bucket = aws_s3_bucket.access.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access" {
  bucket = aws_s3_bucket.access.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access" {
  bucket = aws_s3_bucket.access.id

  rule {
    id     = "expire"
    status = "Enabled"

    filter {}

    expiration {
      days = var.access_log_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.access]
}

resource "aws_s3_bucket_policy" "access" {
  bucket = aws_s3_bucket.access.id
  policy = jsonencode(local.access_policy)

  depends_on = [aws_s3_bucket_public_access_block.access]
}
