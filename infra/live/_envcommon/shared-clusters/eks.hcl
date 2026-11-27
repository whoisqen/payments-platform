locals {
  p = read_terragrunt_config("${get_repo_root()}/infra/live/_envcommon/shared-clusters/profile.hcl").locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//eks"
}

# The argocd access entry names <prefix>-<env>-argocd-controller, which argocd-access of the environment creates.
dependencies {
  paths = ["${dirname(find_in_parent_folders("env.hcl"))}/eu-central-1/argocd-access"]
}

# Cluster pay-<env>-<region-short>-eks-<cluster>; Argo CD knows it as pay-<env>-<region-short>-<cluster>, the destination of the ApplicationSets.
inputs = {
  component                = "eks-${local.p.path.cluster}"
  kubernetes_version       = local.p.env_cfg.kubernetes_version
  permissions_boundary_arn = local.p.env_cfg.permissions_boundary_arn
  access_entries           = local.p.env_cfg.access_entries
  log_retention_days       = local.p.env_cfg.eks_log_retention_days
  tags = {
    team        = local.p.profile.team
    owner       = local.p.env_cfg.owner
    pci-scope   = local.p.profile.pci_scope
    data-class  = local.p.profile.data_class
    backup-tier = "none"
  }
}
