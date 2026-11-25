# Management account: Organizations, billing and IAM Identity Center only, no workloads; values come from config/platform.yaml.
locals {
  cfg = yamldecode(file("${get_repo_root()}/config/platform.yaml"))

  environment = "management"
  # Placeholder until accounts.management is set: the provider then refuses every call (allowed_account_ids).
  account_id                 = try(local.cfg.accounts.management, "000000000000")
  shared_services_account_id = local.cfg.accounts.shared_services
  owner                      = local.cfg.owner.contact_email
  cost_center                = "${local.cfg.owner.cost_center_prefix}-management"
  state_kms_key_arn          = local.cfg.storage.state_kms_key_arn
}
