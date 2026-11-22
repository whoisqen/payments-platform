locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//secrets-replica"
}

inputs = {
  secrets = {
    router         = { description = "Router configuration and PSP credentials" }
    locker         = { description = "Locker configuration" }
    drainer        = { description = "Drainer configuration" }
    scheduler      = { description = "Scheduler configuration" }
    control-center = { description = "Control center configuration" }
  }
  tags = {
    team        = "security"
    owner       = local.env_cfg.owner
    pci-scope   = "cde"
    data-class  = "internal"
    backup-tier = "silver"
  }
}
