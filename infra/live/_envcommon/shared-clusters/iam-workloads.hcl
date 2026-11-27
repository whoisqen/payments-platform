locals {
  p = read_terragrunt_config("${get_repo_root()}/infra/live/_envcommon/shared-clusters/profile.hcl").locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//iam-workloads"
}

inputs = {
  cell                     = local.p.path.cluster
  services                 = local.p.profile.services
  permissions_boundary_arn = local.p.env_cfg.permissions_boundary_arn
  tags = {
    team        = local.p.profile.team
    owner       = local.p.env_cfg.owner
    pci-scope   = local.p.profile.pci_scope
    data-class  = local.p.profile.data_class
    backup-tier = "none"
  }
}
