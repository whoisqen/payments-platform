locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//global-accelerator"
}

inputs = {
  endpoint_groups = {
    "eu-central-1" = { active = true }
    "us-east-1"    = { active = false }
    "us-east-2"    = { active = false }
  }
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "connected"
    data-class  = "public"
    backup-tier = "none"
  }
}
