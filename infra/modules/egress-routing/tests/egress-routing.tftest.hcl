mock_provider "aws" {}

variables {
  azs                        = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  transit_gateway_id         = "tgw-0123456789abcdef0"
  workload_cidrs             = ["10.120.0.0/16"]
  attachment_route_table_ids = ["rtb-data0", "rtb-data1", "rtb-data2"]
  firewall_route_table_ids   = ["rtb-fw0", "rtb-fw1", "rtb-fw2"]
  nat_route_table_ids        = ["rtb-pub0", "rtb-pub1", "rtb-pub2"]
  firewall_endpoint_ids      = { "eu-central-1a" = "vpce-a", "eu-central-1b" = "vpce-b", "eu-central-1c" = "vpce-c" }
  nat_gateway_ids            = ["nat-0", "nat-1", "nat-2"]
}

run "attachment_subnets_go_to_the_firewall_of_their_az" {
  command = plan

  assert {
    condition     = alltrue([for k, r in aws_route.attachment_to_firewall : r.destination_cidr_block == "0.0.0.0/0" && r.route_table_id == "rtb-data${k}"]) && aws_route.attachment_to_firewall["1"].vpc_endpoint_id == "vpce-b"
    error_message = "transit gateway traffic enters the firewall endpoint of the same AZ"
  }
}

run "firewall_subnets_go_to_nat_and_back_to_the_transit_gateway" {
  command = plan

  assert {
    condition     = alltrue([for k, r in aws_route.firewall_to_nat : r.route_table_id == "rtb-fw${k}" && r.nat_gateway_id == "nat-${k}" && r.destination_cidr_block == "0.0.0.0/0"])
    error_message = "inspected traffic leaves through the NAT gateway of the same AZ"
  }
  assert {
    condition     = length(aws_route.firewall_to_workloads) == 3 && alltrue([for r in aws_route.firewall_to_workloads : r.transit_gateway_id == "tgw-0123456789abcdef0" && r.destination_cidr_block == "10.120.0.0/16"])
    error_message = "inspected return traffic goes back to the transit gateway"
  }
}

run "nat_return_traffic_goes_through_the_same_firewall_endpoint" {
  command = plan

  assert {
    condition     = aws_route.nat_return_through_firewall["0-10.120.0.0/16"].route_table_id == "rtb-pub0" && aws_route.nat_return_through_firewall["0-10.120.0.0/16"].vpc_endpoint_id == "vpce-a" && aws_route.nat_return_through_firewall["2-10.120.0.0/16"].vpc_endpoint_id == "vpce-c"
    error_message = "the return path is symmetric per AZ, so the stateful firewall sees both directions"
  }
}

run "several_workload_cidrs" {
  command = plan

  variables {
    workload_cidrs = ["10.120.0.0/16", "10.140.0.0/16"]
  }

  assert {
    condition     = length(aws_route.firewall_to_workloads) == 6 && length(aws_route.nat_return_through_firewall) == 6
    error_message = "one return route per workload CIDR and AZ"
  }
}

run "shared_public_route_table_is_rejected" {
  command = plan

  variables {
    nat_route_table_ids = ["rtb-pub", "rtb-pub", "rtb-pub"]
  }

  expect_failures = [var.nat_route_table_ids]
}

run "default_route_as_workload_is_rejected" {
  command = plan

  variables {
    workload_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.workload_cidrs]
}
