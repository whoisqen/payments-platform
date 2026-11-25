locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//karpenter"
}

# Pools stateful (ClickHouse, Keeper) and workers only: the analytics cluster holds no CDE workload.
inputs = {
  bottlerocket_version     = local.env_cfg.bottlerocket_version
  permissions_boundary_arn = local.env_cfg.permissions_boundary_arn
  enabled_pools            = ["stateful", "workers"]
  cpu_limits               = local.env_cfg.analytics.cpu_limits
  spot_pools               = local.env_cfg.analytics.spot_pools
  tags = {
    team        = "data"
    owner       = local.env_cfg.owner
    pci-scope   = "out-of-scope"
    data-class  = "internal"
    backup-tier = "none"
  }
}
