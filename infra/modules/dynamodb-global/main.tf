locals {
  name              = "${var.name_prefix}-${var.env}-${var.region_short}-${var.component}"
  deny_write_region = coalesce(var.deny_write_regions, keys(var.recovery_regions))

  deny_write_resources = flatten([
    for r in local.deny_write_region : [
      "arn:aws:dynamodb:${r}:${var.account_id}:table/${local.name}",
      "arn:aws:dynamodb:${r}:${var.account_id}:table/${local.name}/index/*",
    ]
  ])
}

# MREC mode: replicas converge eventually and only Frankfurt writes, so no conflict resolution is needed.
resource "aws_dynamodb_table" "this" {
  name                        = local.name
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = var.hash_key
  stream_enabled              = true
  stream_view_type            = "NEW_AND_OLD_IMAGES"
  deletion_protection_enabled = var.deletion_protection

  attribute {
    name = var.hash_key
    type = "S"
  }

  point_in_time_recovery {
    enabled                 = true
    recovery_period_in_days = var.pitr_days
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  dynamic "replica" {
    for_each = var.recovery_regions

    content {
      region_name                 = replica.key
      kms_key_arn                 = replica.value.kms_key_arn
      point_in_time_recovery      = true
      propagate_tags              = true
      deletion_protection_enabled = var.deletion_protection
      consistency_mode            = "EVENTUAL"
    }
  }

  tags = var.tags
}

# Attached to every service role; the switch removes a region from deny_write_regions.
resource "aws_iam_policy" "deny_recovery_writes" {
  name        = "${local.name}-deny-recovery-writes"
  description = "Denies writes to the merchant-to-cell map in regions that must not write"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyWritesInRecoveryRegions"
      Effect = "Deny"
      Action = [
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:BatchWriteItem",
        "dynamodb:TransactWriteItems",
      ]
      Resource = local.deny_write_resources
    }]
  })

  tags = var.tags
}
