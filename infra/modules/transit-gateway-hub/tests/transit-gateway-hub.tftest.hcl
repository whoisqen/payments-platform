mock_provider "aws" {}

variables {
  name_prefix        = "pay"
  region             = "eu-central-1"
  transit_gateway_id = "tgw-0000000000000hub0"
  hub_route_table_id = "tgw-rtb-000000000shared"
  hub_attachment_id  = "tgw-attach-0000000shared"
  hub_cidrs          = ["10.140.0.0/19", "10.140.32.0/19", "10.140.64.0/19"]
  spokes = {
    dev-euc1   = { account_id = "111111111111", region = "eu-central-1", transit_gateway_id = "tgw-dev", cidrs = ["10.120.0.0/16"], accepted = true }
    stage-euc1 = { account_id = "333333333333", region = "eu-central-1", transit_gateway_id = "tgw-stage", cidrs = ["10.130.0.0/16"], accepted = true }
    prod-euc1  = { account_id = "444444444444", region = "eu-central-1", transit_gateway_id = "tgw-prod", cidrs = ["10.150.0.0/16"], accepted = true }
    prod-use1  = { account_id = "444444444444", region = "us-east-1", transit_gateway_id = "tgw-prod-use1", cidrs = ["10.151.0.0/16"] }
  }
  tags = {
    team = "platform", owner = "platform@example.com", pci-scope = "connected", data-class = "internal", backup-tier = "none"
  }
}

run "one_peering_and_table_per_spoke" {
  command = plan

  assert {
    condition     = length(aws_ec2_transit_gateway_peering_attachment.this) == 4 && length(aws_ec2_transit_gateway_route_table.spoke) == 4
    error_message = "every spoke gets its own peering and its own hub route table"
  }
  assert {
    condition     = aws_ec2_transit_gateway_peering_attachment.this["prod-use1"].peer_region == "us-east-1" && aws_ec2_transit_gateway_peering_attachment.this["prod-use1"].peer_account_id == "444444444444"
    error_message = "the standby region peers directly with the hub"
  }
}

run "pending_peering_has_no_association_or_route" {
  command = plan

  assert {
    condition     = !contains(keys(aws_ec2_transit_gateway_route_table_association.spoke), "prod-use1") && length([for k in keys(aws_ec2_transit_gateway_route.to_spoke) : k if startswith(k, "prod-use1/")]) == 0
    error_message = "a peering that is not accepted is neither associated nor routed to"
  }
  assert {
    condition     = length(aws_ec2_transit_gateway_route_table_association.spoke) == 3
    error_message = "accepted peerings are associated"
  }
}

run "spoke_tables_route_only_to_the_hub" {
  command = plan

  assert {
    condition     = length(aws_ec2_transit_gateway_route.to_hub) == 9 && alltrue([for r in values(aws_ec2_transit_gateway_route.to_hub) : contains(var.hub_cidrs, r.destination_cidr_block) && r.transit_gateway_attachment_id == var.hub_attachment_id])
    error_message = "a spoke table holds the hub CIDRs to the shared-services attachment and nothing else"
  }
  assert {
    condition = alltrue([for k, r in aws_ec2_transit_gateway_route.to_hub : alltrue([
      for s, v in var.spokes : !contains(v.cidrs, r.destination_cidr_block)
    ])])
    error_message = "no spoke table carries the CIDR of any spoke, so there is no route between environments"
  }
}

run "hub_table_routes_each_spoke_to_its_own_peering" {
  command = plan

  assert {
    condition = length(aws_ec2_transit_gateway_route.to_spoke) == 3 && alltrue([
      for k, r in aws_ec2_transit_gateway_route.to_spoke : r.transit_gateway_route_table_id == var.hub_route_table_id && contains(var.spokes[split("/", k)[0]].cidrs, r.destination_cidr_block)
    ])
    error_message = "the shared-services table sends each environment CIDR to that environment's peering only"
  }
}

run "overlapping_spokes_rejected" {
  command = plan

  variables {
    spokes = {
      dev-euc1   = { account_id = "111111111111", region = "eu-central-1", transit_gateway_id = "tgw-dev", cidrs = ["10.120.0.0/16"] }
      stage-euc1 = { account_id = "333333333333", region = "eu-central-1", transit_gateway_id = "tgw-stage", cidrs = ["10.120.128.0/17"] }
    }
  }

  expect_failures = [var.spokes]
}
