locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  # Hot standby: us-east-1 takes the whole load at any moment, so its node pools have the working limits.
  cpu_limits = local.env_cfg.karpenter_cpu_limits
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
