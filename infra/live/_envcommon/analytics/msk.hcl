locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//msk"
}

inputs = {
  broker_count        = local.env_cfg.analytics.msk.broker_count
  instance_type       = local.env_cfg.analytics.msk.instance_type
  volume_size_gb      = local.env_cfg.analytics.msk.volume_size_gb
  enhanced_monitoring = local.env_cfg.analytics.msk.enhanced_monitoring
  tags = {
    team        = "data"
    owner       = local.env_cfg.owner
    pci-scope   = "out-of-scope"
    data-class  = "internal"
    backup-tier = "none"
  }
}
