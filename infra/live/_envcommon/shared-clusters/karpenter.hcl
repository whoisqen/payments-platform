locals {
  p = read_terragrunt_config("${get_repo_root()}/infra/live/_envcommon/shared-clusters/profile.hcl").locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//karpenter"
}

inputs = {
  bottlerocket_version     = local.p.env_cfg.bottlerocket_version
  permissions_boundary_arn = local.p.env_cfg.permissions_boundary_arn
  enabled_pools            = local.p.profile.pools
  cpu_limits               = local.p.cpu_limits
  spot_pools               = local.p.profile.spot_pools
  workers_spot             = local.p.profile.workers_spot
  tags = {
    team        = local.p.profile.team
    owner       = local.p.env_cfg.owner
    pci-scope   = local.p.profile.pci_scope
    data-class  = local.p.profile.data_class
    backup-tier = "none"
  }
}
