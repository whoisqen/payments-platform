locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//network-firewall"
}

inputs = {
  psp_domains       = local.env_cfg.psp_domains
  delete_protection = local.env_cfg.deletion_protection
  tags = {
    team        = "security"
    owner       = local.env_cfg.owner
    pci-scope   = "connected"
    data-class  = "internal"
    backup-tier = "none"
  }
}
