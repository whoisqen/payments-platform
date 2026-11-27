locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  cfg     = local.env_cfg.cfg

  # eu-central-1 -> euc1, the region short code of the naming scheme
  working_parts = split("-", local.cfg.regions.working)
  working_short = "${substr(local.working_parts[0], 0, 2)}${substr(local.working_parts[1], 0, 1)}${local.working_parts[2]}"
}

terraform {
  source = "${get_repo_root()}/infra/modules//dr-failover"
}

inputs = {
  source_region       = local.cfg.regions.working
  source_region_short = local.working_short
  # Every Aurora global cluster that a cell or the locker owns.
  cells            = concat(local.env_cfg.cells, ["locker"])
  fence_rule_group = "${local.cfg.naming.prefix}-${local.env_cfg.environment}-${local.working_short}-psp-fence"
  # Hot standby keeps a writer-class instance per cluster; only the fallback with standby compute off adds writers (units override spare and locker).
  switch_writer_instance_classes = local.env_cfg.standby_enabled ? {} : { for c in concat(local.env_cfg.cells, ["locker"]) : c => local.env_cfg.aurora_writer_class }
  # The hot standby already runs its compute; the build workflow (config/platform.yaml deploy.<env>.dr_compute_build) is dispatched only in the fallback.
  compute_build = local.env_cfg.standby_compute_enabled ? null : try(local.cfg.deploy[local.env_cfg.environment].dr_compute_build, null)
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "cde"
    data-class  = "internal"
    backup-tier = "gold"
  }
}
