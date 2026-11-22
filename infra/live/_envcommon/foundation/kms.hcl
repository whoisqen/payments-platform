locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//kms-set"
}

inputs = {
  keys = local.env_cfg.kms_keys
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "cde"
    data-class  = "card-data"
    backup-tier = "none"
  }
}
