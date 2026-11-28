locals {
  region_short = join("", [split("-", var.region)[0], substr(split("-", var.region)[1], 0, 1), split("-", var.region)[2]])
  name         = "${var.name_prefix}-${var.environment}-${local.region_short}-${var.component}"

  accepted = { for k, s in var.spokes : k => s if s.accepted }

  to_hub   = merge([for k, s in local.accepted : { for c in var.hub_cidrs : "${k}/${c}" => { spoke = k, cidr = c } }]...)
  to_spoke = merge([for k, s in local.accepted : { for c in s.cidrs : "${k}/${c}" => { spoke = k, cidr = c } }]...)
}

resource "aws_ec2_transit_gateway_peering_attachment" "this" {
  for_each = var.spokes

  transit_gateway_id      = var.transit_gateway_id
  peer_account_id         = each.value.account_id
  peer_region             = each.value.region
  peer_transit_gateway_id = each.value.transit_gateway_id
  tags                    = merge(var.tags, { Name = "${local.name}-${each.key}" })
}

# One table per peering holding only the hub destinations, so a spoke never learns another spoke's CIDR.
resource "aws_ec2_transit_gateway_route_table" "spoke" {
  for_each = var.spokes

  transit_gateway_id = var.transit_gateway_id
  tags               = merge(var.tags, { Name = "${local.name}-${each.key}" })
}

# A pending peering cannot be associated or routed to, hence the accepted flag.
resource "aws_ec2_transit_gateway_route_table_association" "spoke" {
  for_each = local.accepted

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.this[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke[each.key].id
}

resource "aws_ec2_transit_gateway_route" "to_hub" {
  for_each = local.to_hub

  destination_cidr_block         = each.value.cidr
  transit_gateway_attachment_id  = var.hub_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke[each.value.spoke].id
}

resource "aws_ec2_transit_gateway_route" "to_spoke" {
  for_each = local.to_spoke

  destination_cidr_block         = each.value.cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.this[each.value.spoke].id
  transit_gateway_route_table_id = var.hub_route_table_id

  depends_on = [aws_ec2_transit_gateway_route_table_association.spoke]
}
