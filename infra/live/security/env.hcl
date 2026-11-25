# Security OU: two accounts in one environment, so the account follows the component (log-archive or audit).
locals {
  cfg = yamldecode(file("${get_repo_root()}/config/platform.yaml"))

  environment = "security"
  component   = basename(get_original_terragrunt_dir())

  log_archive_account_id     = try(local.cfg.accounts.log_archive, "000000000002")
  audit_account_id           = try(local.cfg.accounts.audit, "000000000003")
  account_id                 = local.component == "log-archive" ? local.log_archive_account_id : local.audit_account_id
  shared_services_account_id = local.cfg.accounts.shared_services
  owner                      = local.cfg.owner.contact_email
  cost_center                = "${local.cfg.owner.cost_center_prefix}-security"

  state_kms_key_arn = local.cfg.storage.state_kms_key_arn
}
