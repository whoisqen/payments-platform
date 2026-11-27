locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  cfg     = local.env_cfg.cfg
}

terraform {
  source = "${get_repo_root()}/infra/modules//argocd-access"
}

inputs = {
  mode                       = local.env_cfg.environment == "shared-services" ? "hub" : "spoke"
  shared_services_account_id = local.cfg.accounts.shared_services
  spoke_account_ids          = { for env in ["dev", "stage", "prod"] : env => local.cfg.accounts[env] }
  permissions_boundary_arn   = local.env_cfg.permissions_boundary_arn
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "connected"
    data-class  = "internal"
    backup-tier = "none"
  }
}
