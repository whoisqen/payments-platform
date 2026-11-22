locals {
  # One file per OU keeps a new account a one-block pull request.
  ou_files = ["infrastructure", "workloads-cde", "workloads-noncde", "sandbox"]

  accounts = merge([
    for f in local.ou_files : { for a in yamldecode(file("${path.module}/accounts/${f}.yaml")).accounts : a.name => merge(a, { ou = yamldecode(file("${path.module}/accounts/${f}.yaml")).ou }) }
  ]...)
}

module "request" {
  source   = "./modules/account-request"
  for_each = local.accounts

  name                        = each.value.name
  email                       = each.value.email
  ou                          = each.value.ou
  sso_user                    = each.value.sso_user
  account_customizations_name = each.value.customizations
  request_table_name          = var.request_table_name
  tags                        = merge(each.value.tags, { managed-by = "aft" })
}
