include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/foundation/egress-routing.hcl"
  expose = true
}

dependency "egress_vpc" {
  config_path = "../egress-vpc"

  mock_outputs = {
    data_route_table_ids    = ["rtb-c00000000", "rtb-c10000000", "rtb-c20000000"]
    private_route_table_ids = ["rtb-b00000000", "rtb-b10000000", "rtb-b20000000"]
    public_route_table_ids  = ["rtb-a00000000", "rtb-a10000000", "rtb-a20000000"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "firewall" {
  config_path = "../firewall"

  mock_outputs = {
    firewall_endpoint_ids = { for az in include.envcommon.locals.env_cfg.azs[include.envcommon.locals.region] : az => "vpce-00000000" }
    nat_gateway_ids       = ["nat-00000000", "nat-10000000", "nat-20000000"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "tgw" {
  config_path = "../tgw"

  mock_outputs = {
    transit_gateway_id = "tgw-00000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

# Attachment subnets (data) -> firewall endpoints (private) -> NAT (public) and back, per AZ.
inputs = {
  transit_gateway_id         = dependency.tgw.outputs.transit_gateway_id
  attachment_route_table_ids = dependency.egress_vpc.outputs.data_route_table_ids
  firewall_route_table_ids   = dependency.egress_vpc.outputs.private_route_table_ids
  nat_route_table_ids        = dependency.egress_vpc.outputs.public_route_table_ids
  firewall_endpoint_ids      = dependency.firewall.outputs.firewall_endpoint_ids
  nat_gateway_ids            = dependency.firewall.outputs.nat_gateway_ids
}
