locals {
  env_cfg      = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  hub          = read_terragrunt_config("${get_repo_root()}/infra/live/_envcommon/hub-network.hcl").locals
  region       = regex("/live/[^/]+/(?P<region>[^/]+)/", get_terragrunt_dir()).region
  region_short = { "eu-central-1" = "euc1", "us-east-1" = "use1" }[local.region]
  spoke        = "${local.env_cfg.environment}-${local.region_short}"
}

terraform {
  source = "${get_repo_root()}/infra/modules//transit-gateway-spoke"
}

dependency "tgw" {
  config_path = "${get_terragrunt_dir()}/../tgw"

  mock_outputs = {
    transit_gateway_id = "tgw-00000000"
    route_table_ids    = { cde = "tgw-rtb-00000000", egress = "tgw-rtb-00000001" }
    attachment_ids     = { cde = "tgw-attach-00000000", egress = "tgw-attach-00000001" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "vpc" {
  config_path = "${get_terragrunt_dir()}/../vpc"

  mock_outputs = {
    vpc_id = "vpc-00000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "hub" {
  config_path = "${get_repo_root()}/infra/live/shared-services/eu-central-1/tgw-hub"

  mock_outputs = {
    peering_attachment_ids = { for k in keys(local.hub.spokes) : k => "tgw-attach-00000000" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "admin_edge" {
  config_path = "${get_repo_root()}/infra/live/shared-services/eu-central-1/admin-edge"

  mock_outputs = {
    zone_id = "Z00000000000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

# Apply after tgw-hub requested the peering and admin-edge authorized this VPC; then list the spoke in hub_peering_accepted of shared-services/env.hcl.
inputs = {
  transit_gateway_id      = dependency.tgw.outputs.transit_gateway_id
  workload_route_table_id = dependency.tgw.outputs.route_table_ids["cde"]
  workload_attachment_id  = dependency.tgw.outputs.attachment_ids["cde"]
  peering_attachment_id   = dependency.hub.outputs.peering_attachment_ids[local.spoke]
  vpc_cidrs               = local.hub.spokes[local.spoke].cidrs
  hub_cidrs               = local.hub.central_cidrs
  vpc_id                  = dependency.vpc.outputs.vpc_id
  admin_zone_id           = dependency.admin_edge.outputs.zone_id
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "connected"
    data-class  = "internal"
    backup-tier = "none"
  }
}
