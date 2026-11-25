locals {
  env_cfg      = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  region       = basename(dirname(get_terragrunt_dir()))
  region_short = { "eu-central-1" = "euc1", "us-east-1" = "use1", "us-east-2" = "use2" }[local.region]
  chaos        = try(local.env_cfg.cfg.chaos[local.env_cfg.environment], {})
  name         = "${local.env_cfg.cfg.naming.prefix}-${local.env_cfg.environment}-${local.region_short}"
  roles_exist  = try(local.chaos.fis_roles_exist, false)
  pod_actions  = try(local.chaos.eks_pod_actions, null)
}

terraform {
  source = "${get_repo_root()}/infra/modules//fis-prereqs"
}

# IAM is global: only the eu-central-1 unit of an account creates the boundary. Access entry and role policy wait for fis-experiments (chaos.<env>.fis_roles_exist).
inputs = {
  stop_signal_missing_data = try(local.chaos.stop_signal_missing_data, "breaching")
  edge_target_groups       = try(local.chaos.edge_target_groups, [])
  aurora_cluster_ids       = try(local.chaos.aurora_cluster_ids, [])
  additional_alarm_arns    = try(local.chaos.additional_alarm_arns, [])
  alarm_actions            = try(local.chaos.alarm_actions, [])
  automation_role_exists   = local.roles_exist
  eks_access_entry         = local.roles_exist && local.pod_actions != null ? { cluster_name = local.pod_actions.cluster_name } : null
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "connected"
    data-class  = "internal"
    backup-tier = "none"
  }
}
