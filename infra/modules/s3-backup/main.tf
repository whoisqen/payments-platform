locals {
  working = var.region_role == "working"

  local_bucket = {
    (var.region_name) = {
      short       = var.region_short
      kms_key_arn = var.kms_key_arn
    }
  }

  # A working stack also creates the locked destination buckets, so replication never targets a missing bucket.
  buckets = local.working ? merge(local.local_bucket, var.recovery_regions) : local.local_bucket

  names = { for r, b in local.buckets : r => "${var.name_prefix}-${var.env}-${b.short}-${var.component}" }

  destinations = local.working ? var.recovery_regions : {}
  dest_order   = { for i, r in sort(keys(local.destinations)) : r => i + 1 }

  source_bucket_arn = "arn:aws:s3:::${local.names[var.region_name]}"

  tls_only = {
    Sid       = "DenyInsecureTransport"
    Effect    = "Deny"
    Principal = "*"
    Action    = "s3:*"
    Condition = { Bool = { "aws:SecureTransport" = "false" } }
  }
}

resource "aws_s3_bucket" "this" {
  for_each = local.buckets

  region              = each.key
  bucket              = local.names[each.key]
  object_lock_enabled = true

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = local.buckets

  region = each.key
  bucket = aws_s3_bucket.this[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = local.buckets

  region = each.key
  bucket = aws_s3_bucket.this[each.key].id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = each.value.kms_key_arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = local.buckets

  region                  = each.key
  bucket                  = aws_s3_bucket.this[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Every copy is locked: a compromised admin or a replicated delete cannot shorten the retention.
resource "aws_s3_bucket_object_lock_configuration" "this" {
  for_each = local.buckets

  region = each.key
  bucket = aws_s3_bucket.this[each.key].id

  rule {
    default_retention {
      mode = var.object_lock_mode
      days = var.object_lock_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_policy" "this" {
  for_each = local.buckets

  region = each.key
  bucket = aws_s3_bucket.this[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [merge(local.tls_only, { Resource = ["arn:aws:s3:::${local.names[each.key]}", "arn:aws:s3:::${local.names[each.key]}/*"] })],
      each.key == var.region_name ? var.bucket_policy_statements : [],
    )
  })

  depends_on = [aws_s3_bucket_public_access_block.this]
}

# Cold transitions at 7 and 14 days; the Infrequent Access classes would need 30 days in STANDARD, so Glacier classes are used.
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  for_each = local.buckets

  region = each.key
  bucket = aws_s3_bucket.this[each.key].id

  dynamic "rule" {
    for_each = toset(var.lifecycle_prefixes)

    content {
      id     = "tier-${replace(trimsuffix(rule.value, "/"), "/", "-")}"
      status = "Enabled"

      filter {
        prefix = rule.value
      }

      transition {
        days          = var.cold_after_days
        storage_class = "GLACIER_IR"
      }

      transition {
        days          = var.colder_after_days
        storage_class = "GLACIER"
      }

      expiration {
        days = var.expire_after_days
      }

      noncurrent_version_expiration {
        noncurrent_days = var.object_lock_days
      }
    }
  }

  rule {
    id     = "monthly-archive"
    status = "Enabled"

    filter {
      prefix = var.archive_prefix
    }

    transition {
      days          = 0
      storage_class = "DEEP_ARCHIVE"
    }

    expiration {
      days = var.archive_expire_days
    }
  }

  rule {
    id     = "abort-multipart"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_iam_role" "replication" {
  count = local.working ? 1 : 0

  name = "${var.name_prefix}-${var.env}-${var.region_short}-${var.component}-replication"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "replication" {
  count = local.working ? 1 : 0

  name = "replicate-locked-objects"
  role = aws_iam_role.replication[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
        Resource = [local.source_bucket_arn]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging",
          "s3:GetObjectRetention",
          "s3:GetObjectLegalHold",
        ]
        Resource = ["${local.source_bucket_arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ReplicateObject", "s3:ReplicateTags", "s3:ObjectOwnerOverrideToBucketOwner"]
        Resource = [for r, d in local.destinations : "arn:aws:s3:::${local.names[r]}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [var.kms_key_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Encrypt", "kms:GenerateDataKey"]
        Resource = [for r, d in local.destinations : d.kms_key_arn]
      },
    ]
  })
}

# One rule per recovery region with RTC: 15 minutes is the S3 RPO of D7.
resource "aws_s3_bucket_replication_configuration" "this" {
  count = local.working ? 1 : 0

  region = var.region_name
  bucket = aws_s3_bucket.this[var.region_name].id
  role   = aws_iam_role.replication[0].arn

  dynamic "rule" {
    for_each = local.destinations

    content {
      id       = "to-${rule.key}"
      status   = "Enabled"
      priority = local.dest_order[rule.key]

      filter {}

      delete_marker_replication {
        status = "Disabled"
      }

      source_selection_criteria {
        sse_kms_encrypted_objects {
          status = "Enabled"
        }
      }

      destination {
        bucket        = "arn:aws:s3:::${local.names[rule.key]}"
        storage_class = "STANDARD"

        encryption_configuration {
          replica_kms_key_id = rule.value.kms_key_arn
        }

        replication_time {
          status = "Enabled"

          time {
            minutes = 15
          }
        }

        metrics {
          status = "Enabled"

          event_threshold {
            minutes = 15
          }
        }
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.this, aws_s3_bucket_object_lock_configuration.this]
}

resource "aws_cloudwatch_metric_alarm" "replication_latency" {
  for_each = local.destinations

  region              = var.region_name
  alarm_name          = "${local.names[var.region_name]}-replication-to-${each.key}"
  alarm_description   = "S3 replication latency above the 15 minute RTC target"
  namespace           = "AWS/S3"
  metric_name         = "ReplicationLatency"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 900
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "ignore"
  alarm_actions       = var.alarm_actions

  dimensions = {
    SourceBucket      = local.names[var.region_name]
    DestinationBucket = local.names[each.key]
    RuleId            = "to-${each.key}"
  }

  tags = var.tags
}
