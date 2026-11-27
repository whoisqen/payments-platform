module "replica_use1" {
  source = "./modules/replica-bucket"

  providers = { aws = aws.use1 }

  region           = "us-east-1"
  environment      = var.environment
  name_prefix      = var.name_prefix
  account_id       = var.account_id
  kms_key_arn      = module.state_key_use1.key_arn
  retention_days   = var.state_retention_days
  writer_role_arns = var.dr_apply_role_arns
  tags             = var.tags
}

# The recovery region us-east-2 is withdrawn; its locked replica is forgotten, not deleted, and expires by hand after the retention.
removed {
  from = module.replica_use2

  lifecycle {
    destroy = false
  }
}

resource "aws_iam_role" "replication" {
  name = "${var.name_prefix}-${var.environment}-euc1-tf-state-replication"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = var.account_id } }
    }]
  })

  tags = merge(var.tags, { Name = "${var.name_prefix}-${var.environment}-euc1-tf-state-replication" })
}

resource "aws_iam_role_policy" "replication" {
  name = "replicate-state"
  role = aws_iam_role.replication.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "ReadSourceConfig", Effect = "Allow", Action = ["s3:GetReplicationConfiguration", "s3:ListBucket"], Resource = aws_s3_bucket.state.arn },
      {
        Sid      = "ReadSourceVersions"
        Effect   = "Allow"
        Action   = ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging", "s3:GetObjectRetention", "s3:GetObjectLegalHold"]
        Resource = "${aws_s3_bucket.state.arn}/*"
      },
      {
        Sid      = "WriteReplicas"
        Effect   = "Allow"
        Action   = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"]
        Resource = "${module.replica_use1.bucket_arn}/*"
      },
      { Sid = "DecryptSource", Effect = "Allow", Action = "kms:Decrypt", Resource = module.state_key.key_arn },
      { Sid = "EncryptReplicas", Effect = "Allow", Action = ["kms:Encrypt", "kms:GenerateDataKey"], Resource = module.state_key_use1.key_arn },
    ]
  })
}

# Replication Time Control gives the 15 minute S3 RPO of decision D7; replication_enabled = false holds it during a failback.
resource "aws_s3_bucket_replication_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  role   = aws_iam_role.replication.arn

  dynamic "rule" {
    for_each = {
      use1 = { priority = 1, bucket = module.replica_use1.bucket_arn, key = module.state_key_use1.key_arn }
    }

    content {
      id       = "to-${rule.key}"
      priority = rule.value.priority
      status   = var.replication_enabled ? "Enabled" : "Disabled"

      filter {}

      delete_marker_replication {
        status = "Enabled"
      }

      source_selection_criteria {
        sse_kms_encrypted_objects {
          status = "Enabled"
        }
      }

      destination {
        bucket        = rule.value.bucket
        storage_class = "STANDARD"

        encryption_configuration {
          replica_kms_key_id = rule.value.key
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

  depends_on = [aws_s3_bucket_versioning.state, module.replica_use1]
}
