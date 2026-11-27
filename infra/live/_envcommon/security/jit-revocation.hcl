locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  cfg     = local.env_cfg.cfg
}

terraform {
  source = "${get_repo_root()}/infra/modules//jit-revocation-schedule"
}

inputs = {
  github_repository = "${local.cfg.owner.github_org}/${local.cfg.owner.github_repo}"
  tags = {
    team        = "security"
    owner       = local.env_cfg.owner
    pci-scope   = "connected"
    data-class  = "internal"
    backup-tier = "none"
  }
}
