locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  # Unit path <env>/<region>/<cell>/memorydb: the cell (cell-N or spare) prefixes the user names, unique per region.
  cell = basename(dirname(get_terragrunt_dir()))
  # Hyperswitch cannot sign IAM tokens; its Helm value redisUser must be "<cell>-<service>".
  password_services = ["router", "drainer", "scheduler"]
}

terraform {
  source = "${get_repo_root()}/infra/modules//memorydb"
}

inputs = {
  node_type  = local.env_cfg.memorydb_node_type
  num_shards = local.env_cfg.memorydb_shards
  users      = { for k, v in local.env_cfg.memorydb_users : k => v if !contains(local.password_services, k) }
  # Passwords: Vault secret/<env>/<cell>/<service>/redis, applied with update-user (modules/memorydb README, rotation).
  password_users   = { for k, v in local.env_cfg.memorydb_users : k => v if contains(local.password_services, k) }
  user_name_prefix = "${local.cell}-"
  tags = {
    team        = "payments-core"
    owner       = local.env_cfg.owner
    pci-scope   = "cde"
    data-class  = "pii"
    backup-tier = "silver"
  }
}
