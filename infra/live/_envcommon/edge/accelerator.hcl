locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//global-accelerator"
}

inputs = {
  # Only prod has the us-east-1 standby; dev and stage serve from the working region alone.
  endpoint_groups = merge(
    { "eu-central-1" = { active = true } },
    local.env_cfg.standby_compute_enabled ? { "us-east-1" = { active = false } } : {},
  )
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "connected"
    data-class  = "public"
    backup-tier = "none"
  }
}
