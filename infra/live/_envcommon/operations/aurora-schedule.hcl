locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  region  = regex("/live/[^/]+/(?P<region>[^/]+)/", get_terragrunt_dir()).region
  short   = { "eu-central-1" = "euc1", "us-east-1" = "use1" }[local.region]
}

terraform {
  source = "${get_repo_root()}/infra/modules//aurora-schedule"
}

# Every Aurora cluster of the environment: the cells, the spare and the locker.
inputs = {
  cluster_identifiers = [for c in concat(local.env_cfg.cells, ["locker"]) : "${local.env_cfg.cfg.naming.prefix}-${local.env_cfg.environment}-${local.short}-aurora-${c}"]
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "cde"
    data-class  = "internal"
    backup-tier = "none"
  }
}
