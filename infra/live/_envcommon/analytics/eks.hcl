locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//eks"
}

# Analytics cluster pay-<env>-<region-short>-eks-analytics: ClickHouse and its Keeper, outside the CDE, so never inside a cell cluster.
inputs = {
  component                = "eks-analytics"
  kubernetes_version       = local.env_cfg.kubernetes_version
  permissions_boundary_arn = local.env_cfg.permissions_boundary_arn
  access_entries           = local.env_cfg.analytics_access_entries
  log_retention_days       = local.env_cfg.eks_log_retention_days
  tags = {
    team        = "data"
    owner       = local.env_cfg.owner
    pci-scope   = "out-of-scope"
    data-class  = "internal"
    backup-tier = "none"
  }
}
