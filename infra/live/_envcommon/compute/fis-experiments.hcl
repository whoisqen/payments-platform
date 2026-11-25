locals {
  env_cfg      = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  region       = basename(dirname(get_terragrunt_dir()))
  region_short = { "eu-central-1" = "euc1", "us-east-1" = "use1", "us-east-2" = "use2" }[local.region]
  chaos        = try(local.env_cfg.cfg.chaos[local.env_cfg.environment], {})
  name         = "${local.env_cfg.cfg.naming.prefix}-${local.env_cfg.environment}-${local.region_short}"
  cell         = try(local.chaos.target_cell, "cell-1")
}

terraform {
  source = "${get_repo_root()}/infra/modules//fis-experiments"
}

# Names follow tests/chaos/fis; the chaos-stop alarm is owned by observability and must exist before apply.
inputs = {
  stop_alarm_arns          = try(local.chaos.stop_alarm_arns, ["arn:aws:cloudwatch:${local.region}:${local.env_cfg.account_id}:alarm:${local.name}-chaos-stop"])
  target_cell              = local.cell
  target_az                = try(local.chaos.target_az, local.env_cfg.azs[local.region][0])
  memorydb_cluster_name    = try(local.chaos.memorydb_cluster_name, "${local.name}-memorydb-${local.cell}")
  permissions_boundary_arn = try(local.chaos.permissions_boundary_arn, "arn:aws:iam::${local.env_cfg.account_id}:policy/fis-experiment-boundary")
  eks_pod_actions          = try(local.chaos.eks_pod_actions, null)
  psp_latency              = try(local.chaos.psp_latency, null)
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "connected"
    data-class  = "internal"
    backup-tier = "none"
  }
}
