locals {
  working = var.region_role == "working"

  local_vault = {
    (var.region_name) = {
      short       = var.region_short
      kms_key_arn = var.kms_key_arn
    }
  }

  # A working stack also owns the vaults in the recovery regions that receive the copies.
  vaults = local.working ? merge(local.local_vault, var.recovery_regions) : local.local_vault

  vault_names = { for r, v in local.vaults : r => "pay-${var.env}-${v.short}-${var.component}" }
}

resource "aws_backup_vault" "this" {
  for_each = local.vaults

  region      = each.key
  name        = local.vault_names[each.key]
  kms_key_arn = each.value.kms_key_arn

  tags = var.tags
}

# Compliance mode needs a cooling-off period; after it nobody, not even root, can delete a copy early.
resource "aws_backup_vault_lock_configuration" "this" {
  for_each = var.vault_lock_enabled ? local.vaults : {}

  region              = each.key
  backup_vault_name   = aws_backup_vault.this[each.key].name
  min_retention_days  = var.min_retention_days
  max_retention_days  = var.max_retention_days
  changeable_for_days = var.vault_lock_cooling_off_days
}

# The only way into the vault is a copy job from a source account; nothing is readable from outside.
resource "aws_backup_vault_policy" "this" {
  for_each = length(var.source_account_ids) > 0 ? local.vaults : {}

  region            = each.key
  backup_vault_name = aws_backup_vault.this[each.key].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCopyFromSourceAccounts"
      Effect    = "Allow"
      Principal = { AWS = [for a in var.source_account_ids : "arn:aws:iam::${a}:root"] }
      Action    = "backup:CopyIntoBackupVault"
      Resource  = "*"
    }]
  })
}

resource "aws_backup_vault_notifications" "this" {
  for_each = { for r, v in local.vaults : r => v if contains(keys(var.sns_topic_arns), r) }

  region            = each.key
  backup_vault_name = aws_backup_vault.this[each.key].name
  sns_topic_arn     = var.sns_topic_arns[each.key]

  backup_vault_events = [
    "BACKUP_JOB_FAILED",
    "BACKUP_JOB_EXPIRED",
    "COPY_JOB_FAILED",
    "RESTORE_JOB_FAILED",
    "RECOVERY_POINT_MODIFIED",
  ]
}
