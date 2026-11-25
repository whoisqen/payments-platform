locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//clickhouse"
}

inputs = {
  alarm_actions = try(local.env_cfg.cfg.analytics.alarm_sns_topic_arns, [])
  tags = {
    team        = "data"
    owner       = local.env_cfg.owner
    pci-scope   = "out-of-scope"
    data-class  = "internal"
    backup-tier = "silver"
  }
}
