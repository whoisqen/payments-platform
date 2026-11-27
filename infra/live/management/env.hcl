# Management account: Organizations, billing, IAM Identity Center, the organization policies and trail and the delegated-administrator designations; no workloads. Values come from config/platform.yaml.
locals {
  cfg = yamldecode(file("${get_repo_root()}/config/platform.yaml"))

  environment                = "management"
  account_id                 = local.cfg.accounts.management
  shared_services_account_id = local.cfg.accounts.shared_services
  owner                      = local.cfg.owner.contact_email
  cost_center                = "${local.cfg.owner.cost_center_prefix}-management"
  state_kms_key_arn          = local.cfg.storage.state_kms_key_arns[local.environment]
}
