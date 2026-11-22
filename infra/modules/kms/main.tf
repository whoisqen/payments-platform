locals {
  region_short = { "eu-central-1" = "euc1", "us-east-1" = "use1", "us-east-2" = "use2" }[var.region]
  name         = "pay-${var.environment}-${local.region_short}-${var.component}"
  is_replica   = var.is_replica
  root_arn     = "arn:aws:iam::${var.account_id}:root"

  statements = concat(
    [{
      Sid       = "AccountRoot"
      Effect    = "Allow"
      Principal = { AWS = local.root_arn }
      Action    = "kms:*"
      Resource  = "*"
    }],
    length(var.admin_role_arns) == 0 ? [] : [{
      Sid       = "KeyAdministration"
      Effect    = "Allow"
      Principal = { AWS = var.admin_role_arns }
      Action = [
        "kms:Create*", "kms:Describe*", "kms:Enable*", "kms:List*", "kms:Put*", "kms:Update*", "kms:Revoke*",
        "kms:Disable*", "kms:Get*", "kms:TagResource", "kms:UntagResource", "kms:ScheduleKeyDeletion",
        "kms:CancelKeyDeletion", "kms:ReplicateKey",
      ]
      Resource = "*"
    }],
    length(var.user_role_arns) == 0 ? [] : [{
      Sid       = "KeyUsage"
      Effect    = "Allow"
      Principal = { AWS = var.user_role_arns }
      Action    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey", "kms:CreateGrant"]
      Resource  = "*"
    }],
    length(var.service_principals) == 0 ? [] : [{
      Sid       = "ServiceUsage"
      Effect    = "Allow"
      Principal = { Service = var.service_principals }
      Action    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
      Resource  = "*"
      Condition = { StringEquals = { "aws:SourceAccount" = var.account_id } }
    }],
  )

  policy = jsonencode({ Version = "2012-10-17", Statement = local.statements })
}

resource "aws_kms_key" "primary" {
  count = local.is_replica ? 0 : 1

  description              = "${local.name} customer managed key"
  enable_key_rotation      = true
  rotation_period_in_days  = 365
  multi_region             = var.multi_region
  deletion_window_in_days  = var.deletion_window_in_days
  policy                   = local.policy
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  key_usage                = "ENCRYPT_DECRYPT"
  tags                     = merge(var.tags, { Name = local.name })
}

# A replica rotates with its primary; the provider has no rotation setting for it.
resource "aws_kms_replica_key" "replica" {
  count = local.is_replica ? 1 : 0

  description             = "${local.name} replica of ${var.primary_key_arn}"
  primary_key_arn         = var.primary_key_arn
  deletion_window_in_days = var.deletion_window_in_days
  policy                  = local.policy
  tags                    = merge(var.tags, { Name = local.name })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${local.name}"
  target_key_id = local.is_replica ? aws_kms_replica_key.replica[0].key_id : aws_kms_key.primary[0].key_id
}
