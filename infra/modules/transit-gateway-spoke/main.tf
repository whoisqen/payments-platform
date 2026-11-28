locals {
  region_short = join("", [split("-", var.region)[0], substr(split("-", var.region)[1], 0, 1), split("-", var.region)[2]])
  name         = "${var.name_prefix}-${var.environment}-${local.region_short}-${var.component}"

  hub_overlaps = flatten([
    for h in var.hub_cidrs : [
      for v in var.vpc_cidrs : v if cidrsubnet("${cidrhost(h, 0)}/${min(tonumber(split("/", h)[1]), tonumber(split("/", v)[1]))}", 0, 0) == cidrsubnet("${cidrhost(v, 0)}/${min(tonumber(split("/", h)[1]), tonumber(split("/", v)[1]))}", 0, 0)
    ]
  ])
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "this" {
  transit_gateway_attachment_id = var.peering_attachment_id
  tags                          = merge(var.tags, { Name = local.name })

  lifecycle {
    precondition {
      condition     = length(local.hub_overlaps) == 0
      error_message = "hub_cidrs must not overlap vpc_cidrs."
    }
  }
}

# Traffic from the hub may go only to this VPC: no egress default and no other attachment in the table.
resource "aws_ec2_transit_gateway_route_table" "hub" {
  transit_gateway_id = var.transit_gateway_id
  tags               = merge(var.tags, { Name = local.name })
}

resource "aws_ec2_transit_gateway_route_table_association" "hub" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.this.transit_gateway_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub.id
}

resource "aws_ec2_transit_gateway_route" "to_vpc" {
  for_each = toset(var.vpc_cidrs)

  destination_cidr_block         = each.key
  transit_gateway_attachment_id  = var.workload_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub.id
}

# More specific than the egress default of the workload table, so only these destinations leave through the peering.
resource "aws_ec2_transit_gateway_route" "to_hub" {
  for_each = toset(var.hub_cidrs)

  destination_cidr_block         = each.key
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.this.transit_gateway_attachment_id
  transit_gateway_route_table_id = var.workload_route_table_id
}

resource "aws_route53_zone_association" "admin" {
  count = var.admin_zone_id == null ? 0 : 1

  zone_id = var.admin_zone_id
  vpc_id  = var.vpc_id

  lifecycle {
    precondition {
      condition     = var.vpc_id != null
      error_message = "vpc_id is required with admin_zone_id."
    }
  }
}
