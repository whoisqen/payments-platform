mock_provider "aws" {}

variables {
  name_prefix             = "pay"
  region                  = "eu-central-1"
  environment             = "prod"
  transit_gateway_id      = "tgw-0000000000000prod"
  peering_attachment_id   = "tgw-attach-00000000peer"
  workload_route_table_id = "tgw-rtb-0000000000000cde"
  workload_attachment_id  = "tgw-attach-000000000cde"
  vpc_cidrs               = ["10.150.0.0/16"]
  hub_cidrs               = ["10.140.0.0/19", "10.140.32.0/19", "10.140.64.0/19"]
  admin_zone_id           = "Z0000000000ADMIN"
  vpc_id                  = "vpc-0000000000000cde0"
  tags = {
    team = "platform", owner = "platform@example.com", pci-scope = "connected", data-class = "internal", backup-tier = "none"
  }
}

run "peering_table_routes_only_to_own_vpc" {
  command = plan

  assert {
    condition     = aws_ec2_transit_gateway_route_table_association.hub.transit_gateway_attachment_id == var.peering_attachment_id
    error_message = "the peering is associated with the hub table"
  }
  assert {
    condition     = length(aws_ec2_transit_gateway_route.to_vpc) == 1 && alltrue([for r in values(aws_ec2_transit_gateway_route.to_vpc) : contains(var.vpc_cidrs, r.destination_cidr_block) && r.transit_gateway_attachment_id == var.workload_attachment_id])
    error_message = "the hub table holds only this VPC, so traffic from the hub cannot transit to egress or another environment"
  }
  assert {
    condition     = alltrue([for r in values(aws_ec2_transit_gateway_route.to_vpc) : !contains(["0.0.0.0/0", "10.120.0.0/16", "10.130.0.0/16", "10.151.0.0/16"], r.destination_cidr_block)])
    error_message = "no default route and no other environment's CIDR in the hub table"
  }
}

run "workload_table_sends_only_hub_cidrs_to_the_peering" {
  command = plan

  assert {
    condition = length(aws_ec2_transit_gateway_route.to_hub) == 3 && alltrue([
      for r in values(aws_ec2_transit_gateway_route.to_hub) : contains(var.hub_cidrs, r.destination_cidr_block) && r.transit_gateway_route_table_id == var.workload_route_table_id && r.transit_gateway_attachment_id == var.peering_attachment_id
    ])
    error_message = "the workload table reaches shared-services through the peering, for the hub CIDRs only"
  }
}

run "admin_zone_is_associated" {
  command = plan

  assert {
    condition     = length(aws_route53_zone_association.admin) == 1 && aws_route53_zone_association.admin[0].vpc_id == var.vpc_id
    error_message = "the workload VPC resolves the admin zone"
  }
}

run "admin_zone_is_optional" {
  command = plan

  variables {
    admin_zone_id = null
  }

  assert {
    condition     = length(aws_route53_zone_association.admin) == 0
    error_message = "no association without a zone"
  }
}

run "hub_overlapping_the_vpc_rejected" {
  command = plan

  variables {
    hub_cidrs = ["10.150.0.0/19"]
  }

  expect_failures = [aws_ec2_transit_gateway_peering_attachment_accepter.this]
}

run "non_environment_rejected" {
  command = plan

  variables {
    environment = "shared-services"
  }

  expect_failures = [var.environment]
}
