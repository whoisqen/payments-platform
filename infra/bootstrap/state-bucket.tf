locals {
  state_bucket = "${var.name_prefix}-${var.environment}-euc1-tf-state-${var.account_id}"
}

resource "aws_s3_bucket" "state" {
  bucket              = local.state_bucket
  object_lock_enabled = true
  force_destroy       = false
  tags                = merge(var.tags, { Name = local.state_bucket })
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Governance lets a corrupt state version be rolled back by a privileged role and nobody else.
resource "aws_s3_bucket_object_lock_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = var.state_retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = module.state_key.key_arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid       = "TlsOnly"
          Effect    = "Deny"
          Principal = "*"
          Action    = "s3:*"
          Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
          Condition = { Bool = { "aws:SecureTransport" = "false" } }
        },
        {
          Sid       = "KmsEncryptedWritesOnly"
          Effect    = "Deny"
          Principal = "*"
          Action    = "s3:PutObject"
          Resource  = "${aws_s3_bucket.state.arn}/*"
          Condition = { StringNotEquals = { "s3:x-amz-server-side-encryption" = "aws:kms" } }
        },
      ],
      # The DR apply role sits in the environment account, so its drills on the working state need this cross-account grant.
      [for st in [
        {
          Sid       = "DrStateReadWrite"
          Effect    = "Allow"
          Principal = { AWS = var.dr_apply_role_arns }
          Action    = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:DeleteObject"]
          Resource  = "${aws_s3_bucket.state.arn}/${var.environment}/*"
        },
        {
          Sid       = "DrStateList"
          Effect    = "Allow"
          Principal = { AWS = var.dr_apply_role_arns }
          Action    = "s3:ListBucket"
          Resource  = aws_s3_bucket.state.arn
          Condition = { StringLike = { "s3:prefix" = ["${var.environment}/*"] } }
        },
      ] : st if length(var.dr_apply_role_arns) > 0],
    )
  })

  depends_on = [aws_s3_bucket_public_access_block.state]
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.state_retention_days + 1
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}
