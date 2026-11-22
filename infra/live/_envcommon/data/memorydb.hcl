locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//memorydb"
}

inputs = {
  node_type  = local.env_cfg.memorydb_node_type
  num_shards = local.env_cfg.memorydb_shards
  users      = local.env_cfg.memorydb_users
  tags = {
    team        = "payments-core"
    owner       = local.env_cfg.owner
    pci-scope   = "cde"
    data-class  = "pii"
    backup-tier = "silver"
  }
}
