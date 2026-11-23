locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//dns-routing"
}

inputs = {
  record_name = "api.${local.env_cfg.zone_name}"
  endpoints   = { for region, host in local.env_cfg.ingress_endpoints : region => { region = region, target_dns = host } }
}
