locals {
  names = { for k, s in var.secrets : k => "${var.name_prefix}-${var.env}-${var.region_short}-${k}" }
}

# Only the container is managed; values are written by Vault or by rotation, never by Terraform.
resource "aws_secretsmanager_secret" "this" {
  for_each = var.secrets

  name                    = local.names[each.key]
  description             = each.value.description
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = var.recovery_window_days

  dynamic "replica" {
    for_each = var.recovery_regions

    content {
      region     = replica.key
      kms_key_id = replica.value.kms_key_arn
    }
  }

  tags = var.tags
}
