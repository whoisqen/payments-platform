locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//backup"
}

inputs = {
  vault_lock_enabled = local.env_cfg.vault_lock_enabled
  source_account_ids = [local.env_cfg.account_id]
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "cde"
    data-class  = "card-data"
    backup-tier = "none"
  }
}
