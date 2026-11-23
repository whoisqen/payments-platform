locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//ecr"
}

inputs = {
  account_id = local.env_cfg.account_id
  # Images are <namespace>/<name>, the path of the workflows, charts and policies
  repository_namespace = local.env_cfg.cfg.registry.ecr_repo_prefix
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "connected"
    data-class  = "internal"
    backup-tier = "none"
  }
}
