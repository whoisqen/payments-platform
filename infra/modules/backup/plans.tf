locals {
  create_plans = local.working && var.create_plans

  copy_destinations = merge(
    { for r in keys(var.recovery_regions) : r => aws_backup_vault.this[r].arn },
    var.copy_vault_arns,
  )

  # Aurora and DynamoDB keep their native tier (D5), so no rule moves a recovery point to cold storage.
  tier_rules = {
    gold = [
      { name = "hourly", schedule = "cron(0 * * * ? *)", delete_after = var.snapshot_retention_days, continuous = false, copy = true },
      { name = "continuous", schedule = "cron(0 5 * * ? *)", delete_after = var.snapshot_retention_days, continuous = true, copy = false },
      { name = "monthly", schedule = "cron(0 3 1 * ? *)", delete_after = var.archive_retention_days, continuous = false, copy = true },
    ]
    silver = [
      { name = "hourly", schedule = "cron(0 * * * ? *)", delete_after = var.snapshot_retention_days, continuous = false, copy = true },
    ]
    bronze = [
      { name = "daily", schedule = "cron(0 2 * * ? *)", delete_after = var.bronze_retention_days, continuous = false, copy = false },
    ]
  }

  plan_vault = aws_backup_vault.this[var.region_name].name
}

resource "aws_iam_role" "backup" {
  count = local.create_plans ? 1 : 0

  name = "pay-${var.env}-${var.region_short}-${var.component}-service"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "backup" {
  for_each = local.create_plans ? toset([
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup",
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores",
    "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Backup",
    "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Restore",
  ]) : toset([])

  role       = aws_iam_role.backup[0].name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "backup_kms" {
  count = local.create_plans ? 1 : 0

  name = "use-data-keys"
  role = aws_iam_role.backup[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kms:Decrypt", "kms:GenerateDataKey*", "kms:DescribeKey", "kms:CreateGrant", "kms:ReEncrypt*"]
      Resource = var.data_kms_key_arns
    }]
  })
}

resource "aws_backup_plan" "tier" {
  for_each = local.create_plans ? local.tier_rules : {}

  name = "pay-${var.env}-${var.region_short}-${each.key}"

  dynamic "rule" {
    for_each = each.value

    content {
      rule_name                = rule.value.name
      target_vault_name        = local.plan_vault
      schedule                 = rule.value.schedule
      start_window             = 60
      completion_window        = rule.value.name == "monthly" ? 720 : 240
      enable_continuous_backup = rule.value.continuous

      lifecycle {
        delete_after = rule.value.delete_after
      }

      dynamic "copy_action" {
        for_each = rule.value.copy ? local.copy_destinations : {}

        content {
          destination_vault_arn = copy_action.value

          lifecycle {
            delete_after = rule.value.delete_after
          }
        }
      }
    }
  }

  tags = var.tags
}

# Selection by tag: a new stateful resource with a backup-tier tag joins its plan without a code change.
resource "aws_backup_selection" "tier" {
  for_each = local.create_plans ? local.tier_rules : {}

  name         = "pay-${var.env}-${var.region_short}-${each.key}"
  plan_id      = aws_backup_plan.tier[each.key].id
  iam_role_arn = aws_iam_role.backup[0].arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "backup-tier"
    value = each.key
  }
}
