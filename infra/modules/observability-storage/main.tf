locals {
  names = { for k, _ in var.buckets : k => "${var.name_prefix}-${var.environment}-${var.region_short}-${k}" }
  arns  = { for k, n in local.names : k => "arn:aws:s3:::${n}" }
}

resource "aws_s3_bucket" "this" {
  for_each = var.buckets

  bucket = local.names[each.key]

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = var.buckets

  bucket = aws_s3_bucket.this[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = var.buckets

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = var.buckets

  bucket                  = aws_s3_bucket.this[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "this" {
  for_each = var.buckets

  bucket = aws_s3_bucket.this[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [local.arns[each.key], "${local.arns[each.key]}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.this]
}

# Loki, Tempo and Sentry write objects and never tier them; the bucket expires them after the retention of the component.
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  for_each = var.buckets

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    id     = "expire-objects"
    status = "Enabled"

    filter {}

    # A bucket of incremental backups has no age expiry: a new backup reuses files of the earlier ones, and the tool deletes the files it no longer needs
    dynamic "expiration" {
      for_each = each.value.retention_days == null ? [] : [each.value.retention_days]

      content {
        days = expiration.value
      }
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "expire-delete-markers"
    status = "Enabled"

    filter {}

    expiration {
      expired_object_delete_marker = true
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

# One role per bucket, assumed by one service account through Pod Identity.
resource "aws_iam_role" "this" {
  for_each = var.buckets

  name                 = "${local.names[each.key]}-pod"
  permissions_boundary = var.permissions_boundary_arn

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

resource "aws_iam_role_policy" "this" {
  for_each = var.buckets

  name = "bucket-access"
  role = aws_iam_role.this[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:ListBucketMultipartUploads", "s3:GetBucketLocation"]
        Resource = [local.arns[each.key]]
      },
      {
        Sid      = "ReadWriteDeleteObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
        Resource = ["${local.arns[each.key]}/*"]
      },
      # The key is shared by the three buckets; the S3 encryption context (the bucket ARN) keeps each role to its own bucket.
      {
        Sid       = "BucketKey"
        Effect    = "Allow"
        Action    = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource  = [var.kms_key_arn]
        Condition = { StringLike = { "kms:EncryptionContext:aws:s3:arn" = [local.arns[each.key], "${local.arns[each.key]}/*"] } }
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "this" {
  for_each = var.buckets

  cluster_name    = var.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = aws_iam_role.this[each.key].arn

  tags = var.tags
}
