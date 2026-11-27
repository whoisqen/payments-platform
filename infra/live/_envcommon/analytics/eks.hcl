locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  cfg     = local.env_cfg.cfg
  region  = regex("/live/[^/]+/(?P<region>[^/]+)/", get_terragrunt_dir()).region
  # Control-plane logs stream to the log archive (Object Lock, one year) from the working region, where the archive bucket is.
  log_archive = local.region == local.cfg.regions.working ? {
    bucket_arn = "arn:aws:s3:::${local.cfg.naming.prefix}-security-euc1-log-archive"
    account_id = try(local.cfg.accounts.log_archive, "000000000002")
  } : null
  # PCI DSS 10.5.1: a cluster without the export keeps one year in CloudWatch whatever config/environments says.
  log_retention_days = local.log_archive != null ? local.env_cfg.eks_log_retention_days : max(local.env_cfg.eks_log_retention_days, 365)
}

terraform {
  source = "${get_repo_root()}/infra/modules//eks"
}

# The argocd access entry names <prefix>-<env>-argocd-controller, which argocd-access of the environment creates.
dependencies {
  paths = ["${dirname(find_in_parent_folders("env.hcl"))}/eu-central-1/argocd-access"]
}

# Analytics cluster pay-<env>-<region-short>-eks-analytics: ClickHouse and its Keeper, outside the CDE, so never inside a cell cluster.
inputs = {
  component                = "eks-analytics"
  kubernetes_version       = local.env_cfg.kubernetes_version
  permissions_boundary_arn = local.env_cfg.permissions_boundary_arn
  access_entries           = local.env_cfg.analytics_access_entries
  log_retention_days       = local.log_retention_days
  log_archive              = local.log_archive
  tags = {
    team        = "data"
    owner       = local.env_cfg.owner
    pci-scope   = "out-of-scope"
    data-class  = "internal"
    backup-tier = "none"
  }
}
