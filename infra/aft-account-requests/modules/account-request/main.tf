locals {
  s = { for k, v in var.tags : k => { S = v } }
}

# Same item layout as the aft-account-request module of Account Factory for Terraform.
resource "aws_dynamodb_table_item" "request" {
  table_name = var.request_table_name
  hash_key   = "id"

  item = jsonencode({
    id = { S = var.email }
    control_tower_parameters = { M = {
      AccountEmail              = { S = var.email }
      AccountName               = { S = var.name }
      ManagedOrganizationalUnit = { S = var.ou }
      SSOUserEmail              = { S = var.sso_user.email }
      SSOUserFirstName          = { S = var.sso_user.first_name }
      SSOUserLastName           = { S = var.sso_user.last_name }
    } }
    account_tags                = { M = local.s }
    account_customizations_name = { S = var.account_customizations_name }
    custom_fields               = { M = {} }
    change_reason               = { S = var.change_reason }
  })
}
