locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//dns-certs"
}

inputs = {
  zone_name = local.env_cfg.zone_name
  certificates = {
    api = { domain_name = "api.${local.env_cfg.zone_name}" }
  }
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "connected"
    data-class  = "public"
    backup-tier = "none"
  }
}
