include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  hub     = read_terragrunt_config("${get_repo_root()}/infra/live/_envcommon/hub-network.hcl").locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//transit-gateway-hub"
}

dependency "tgw" {
  config_path = "../tgw"

  mock_outputs = {
    transit_gateway_id = "tgw-00000000"
    route_table_ids    = { shared = "tgw-rtb-00000000", egress = "tgw-rtb-00000001" }
    attachment_ids     = { shared = "tgw-attach-00000000", egress = "tgw-attach-00000001" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "dev_euc1" {
  config_path = "../../../dev/eu-central-1/tgw"

  mock_outputs                            = { transit_gateway_id = "tgw-00000001" }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "stage_euc1" {
  config_path = "../../../stage/eu-central-1/tgw"

  mock_outputs                            = { transit_gateway_id = "tgw-00000002" }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "prod_euc1" {
  config_path = "../../../prod/eu-central-1/tgw"

  mock_outputs                            = { transit_gateway_id = "tgw-00000003" }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "prod_use1" {
  config_path = "../../../prod/us-east-1/tgw"

  mock_outputs                            = { transit_gateway_id = "tgw-00000004" }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

# Two steps: the first apply requests the peerings; after each spoke applied its tgw-spoke unit, list it in hub_peering_accepted and apply again.
inputs = {
  transit_gateway_id = dependency.tgw.outputs.transit_gateway_id
  hub_route_table_id = dependency.tgw.outputs.route_table_ids["shared"]
  hub_attachment_id  = dependency.tgw.outputs.attachment_ids["shared"]
  hub_cidrs          = local.hub.central_cidrs
  spokes = { for k, s in local.hub.spokes : k => {
    account_id = s.account_id
    region     = s.region
    transit_gateway_id = {
      dev-euc1   = dependency.dev_euc1.outputs.transit_gateway_id
      stage-euc1 = dependency.stage_euc1.outputs.transit_gateway_id
      prod-euc1  = dependency.prod_euc1.outputs.transit_gateway_id
      prod-use1  = dependency.prod_use1.outputs.transit_gateway_id
    }[k]
    cidrs    = s.cidrs
    accepted = contains(local.env_cfg.hub_peering_accepted, k)
  } }
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "connected"
    data-class  = "internal"
    backup-tier = "none"
  }
}
