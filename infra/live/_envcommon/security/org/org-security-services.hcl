locals {
  base    = read_terragrunt_config("${get_repo_root()}/infra/live/_envcommon/security/org/baseline.hcl").locals
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//org-security-services"
}

# The same component runs in the management account (delegation) and in the audit account (organization-wide settings).
inputs = {
  mode                    = local.env_cfg.environment == "management" ? "management" : "admin"
  regions                 = local.base.regions
  admin_account_id        = local.base.audit_account_id
  root_id                 = local.base.target_ids.root
  member_account_ids      = local.base.member_account_ids
  cde_account_ids         = local.base.cde_account_ids
  shield_advanced_enabled = try(local.base.sec.shield_advanced_enabled, false)
  tags                    = local.base.tags
}
