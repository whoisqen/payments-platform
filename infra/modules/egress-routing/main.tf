locals {
  az_index = { for i, az in var.azs : tostring(i) => az }
  # Each workload CIDR in each AZ: the key stays stable when a CIDR is added.
  az_cidr = merge([for i, az in var.azs : { for c in var.workload_cidrs : "${i}-${c}" => { index = i, az = az, cidr = c } }]...)
}

# Symmetric path through the firewall endpoint of one AZ: attachment subnet -> firewall -> NAT -> internet and back NAT -> firewall -> transit gateway.
resource "aws_route" "attachment_to_firewall" {
  for_each = local.az_index

  route_table_id         = var.attachment_route_table_ids[tonumber(each.key)]
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = var.firewall_endpoint_ids[each.value]
}

resource "aws_route" "firewall_to_nat" {
  for_each = local.az_index

  route_table_id         = var.firewall_route_table_ids[tonumber(each.key)]
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = var.nat_gateway_ids[tonumber(each.key)]
}

resource "aws_route" "firewall_to_workloads" {
  for_each = local.az_cidr

  route_table_id         = var.firewall_route_table_ids[each.value.index]
  destination_cidr_block = each.value.cidr
  transit_gateway_id     = var.transit_gateway_id
}

resource "aws_route" "nat_return_through_firewall" {
  for_each = local.az_cidr

  route_table_id         = var.nat_route_table_ids[each.value.index]
  destination_cidr_block = each.value.cidr
  vpc_endpoint_id        = var.firewall_endpoint_ids[each.value.az]
}
