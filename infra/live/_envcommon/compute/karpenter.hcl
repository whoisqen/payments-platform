locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//karpenter"
}

inputs = {
  bottlerocket_version     = local.env_cfg.bottlerocket_version
  permissions_boundary_arn = local.env_cfg.permissions_boundary_arn
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "cde"
    data-class  = "internal"
    backup-tier = "none"
  }
}
