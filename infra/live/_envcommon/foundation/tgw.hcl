locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//transit-gateway"
}

inputs = {
  route_tables = ["cde", "egress"]
  static_routes = [
    { route_table = "cde", cidr = "0.0.0.0/0", attachment = "egress" },
  ]
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "connected"
    data-class  = "internal"
    backup-tier = "none"
  }
}
