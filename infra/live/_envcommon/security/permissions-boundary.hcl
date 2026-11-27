locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//permissions-boundary"
}

# First stack of an environment account: every role of the other stacks attaches this policy.
inputs = {
  tags = {
    team        = "security"
    owner       = local.env_cfg.owner
    pci-scope   = "connected"
    data-class  = "internal"
    backup-tier = "none"
  }
}
