locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  region  = regex("/live/[^/]+/(?P<region>[^/]+)/", get_terragrunt_dir()).region
  # The standby region keeps small node pools until it is promoted.
  cpu_limits = local.region == local.env_cfg.cfg.regions.working ? local.env_cfg.karpenter_cpu_limits : try(local.env_cfg.standby_node_pool, local.env_cfg.karpenter_cpu_limits)
}

terraform {
  source = "${get_repo_root()}/infra/modules//karpenter"
}

inputs = {
  bottlerocket_version     = local.env_cfg.bottlerocket_version
  permissions_boundary_arn = local.env_cfg.permissions_boundary_arn
  cpu_limits               = local.cpu_limits
  spot_pools               = local.env_cfg.karpenter_spot_pools
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "cde"
    data-class  = "internal"
    backup-tier = "none"
  }
}
