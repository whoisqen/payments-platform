locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//vault-platform"
}

inputs = {
  permissions_boundary_arn = local.env_cfg.permissions_boundary_arn
  tags = {
    team        = "security"
    owner       = local.env_cfg.owner
    pci-scope   = "cde"
    data-class  = "internal"
    backup-tier = "silver"
  }
}
