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
  fallback_region     = local.cfg.regions.recovery[1]
  # Every Aurora global cluster that a cell or the locker owns.
  cells            = concat(local.env_cfg.cells, ["locker"])
  fence_rule_group = "${local.cfg.naming.prefix}-${local.env_cfg.environment}-${local.working_short}-psp-fence"
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "cde"
    data-class  = "internal"
    backup-tier = "gold"
  }
}
