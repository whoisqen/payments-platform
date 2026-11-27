locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  cfg     = local.env_cfg.cfg
}

terraform {
  source = "${get_repo_root()}/infra/modules//runbook-roles"
}

# prod keeps a standby in the first recovery region, so its documents run there too.
inputs = {
  github_repository        = "${local.cfg.owner.github_org}/${local.cfg.owner.github_repo}"
  regions                  = local.env_cfg.environment == "prod" ? [local.cfg.regions.working, local.cfg.regions.recovery[0]] : [local.cfg.regions.working]
  permissions_boundary_arn = local.env_cfg.permissions_boundary_arn
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "connected"
    data-class  = "internal"
    backup-tier = "none"
  }
}
