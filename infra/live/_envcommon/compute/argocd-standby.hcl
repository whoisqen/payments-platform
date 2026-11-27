locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//argocd-standby"
}

# PAY_ARGOCD_INSTALL=true grants the DR apply role cluster-admin on the host for the chart install; the next apply without it revokes it.
inputs = {
  managed_namespaces       = local.env_cfg.access_entries.argocd.namespaces
  installer_role_arn       = get_env("PAY_ARGOCD_INSTALL", "false") == "true" ? local.env_cfg.dr_apply_role_arn : null
  permissions_boundary_arn = local.env_cfg.permissions_boundary_arn
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "cde"
    data-class  = "internal"
    backup-tier = "none"
  }
}
