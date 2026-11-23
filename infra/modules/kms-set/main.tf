module "key" {
  source   = "../kms"
  for_each = var.keys

  account_id         = var.account_id
  region             = var.region
  environment        = var.environment
  name_prefix        = var.name_prefix
  component          = each.key
  is_replica         = var.is_replica
  primary_key_arn    = var.is_replica ? var.primary_key_arns[each.key] : null
  admin_role_arns    = each.value.admin_role_arns
  user_role_arns     = each.value.user_role_arns
  service_principals = each.value.service_principals
  tags               = var.tags
}
