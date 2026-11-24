locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//eks"
}

# The cluster is pay-shared-services-<region-short>-central. Argo CD cluster labels (set on its cluster Secret by the deploy bootstrap):
#   payments-platform/central: enabled
#   payments-platform/addons: enabled
inputs = {
  component                = "central"
  kubernetes_version       = local.env_cfg.kubernetes_version
  permissions_boundary_arn = local.env_cfg.permissions_boundary_arn
  access_entries           = local.env_cfg.access_entries
  log_retention_days       = local.env_cfg.eks_log_retention_days
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "out-of-scope"
    data-class  = "internal"
    backup-tier = "none"
  }
}
