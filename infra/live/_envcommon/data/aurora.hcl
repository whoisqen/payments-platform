locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//aurora-global"
}

inputs = {
  backup_retention_days = 35
  deletion_protection   = local.env_cfg.deletion_protection
  writer_instance_class = local.env_cfg.aurora_writer_class
  reader_instance_class = local.env_cfg.aurora_reader_class
  reader_count          = local.env_cfg.aurora_reader_count
  # Hyperswitch (router, drainer, scheduler) cannot use IAM tokens: one SCRAM login per cell, password in Vault
  # secret/<env>/<cell>/<service>/database. Locker units set their own list, which replaces this one (shallow merge).
  proxy_auth_entries = [{ name = "hs_app", iam_auth = "DISABLED" }]
  tags = {
    team        = "payments-core"
    owner       = local.env_cfg.owner
    pci-scope   = "cde"
    data-class  = "card-data"
    backup-tier = "gold"
  }
}
