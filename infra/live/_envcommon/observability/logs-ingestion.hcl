locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  cfg     = local.env_cfg.cfg
}

terraform {
  source = "${get_repo_root()}/infra/modules//log-ingestion"
}

# The log archive of the security OU (infra/live/security/eu-central-1/log-archive) admits the pipeline role by name.
inputs = {
  permissions_boundary_arn = local.env_cfg.permissions_boundary_arn
  log_archive = {
    bucket_name = "${local.cfg.naming.prefix}-security-euc1-log-archive"
    account_id  = local.cfg.accounts.log_archive
  }
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "out-of-scope"
    data-class  = "internal"
    backup-tier = "none"
  }
}
