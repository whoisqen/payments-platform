# Management account: organization policies, the organization trail and the delegated-administrator designations.
locals {
  cfg = yamldecode(file("${get_repo_root()}/config/platform.yaml"))

  environment                = "management"
  account_id                 = try(local.cfg.accounts.management, "000000000001")
  shared_services_account_id = local.cfg.accounts.shared_services
  owner                      = local.cfg.owner.contact_email
  cost_center                = "${local.cfg.owner.cost_center_prefix}-management"

  state_kms_key_arn = local.cfg.storage.state_kms_key_arn
}
