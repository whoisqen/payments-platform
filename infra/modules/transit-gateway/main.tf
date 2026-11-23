locals {
  region_short = join("", [split("-", var.region)[0], substr(split("-", var.region)[1], 0, 1), split("-", var.region)[2]])
  name         = "${var.name_prefix}-${var.environment}-${local.region_short}-${var.component}"

  propagations = merge([
    for k, a in var.attachments : { for rt in a.propagate_to : "${k}/${rt}" => { attachment = k, route_table = rt } }
  ]...)
}

# Association and propagation are explicit per attachment, so a new VPC is isolated until routed.
resource "aws_ec2_transit_gateway" "this" {
  description                     = local.name
  amazon_side_asn                 = var.amazon_side_asn
  auto_accept_shared_attachments  = "disable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"
  tags                            = merge(var.tags, { Name = local.name })
}

resource "aws_ec2_transit_gateway_route_table" "this" {
  for_each = toset(var.route_tables)

  transit_gateway_id = aws_ec2_transit_gateway.this.id
  tags               = merge(var.tags, { Name = "${local.name}-${each.key}" })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  for_each = var.attachments

  transit_gateway_id                              = aws_ec2_transit_gateway.this.id
  vpc_id                                          = each.value.vpc_id
  subnet_ids                                      = each.value.subnet_ids
  appliance_mode_support                          = each.value.appliance_mode ? "enable" : "disable"
  dns_support                                     = "enable"
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  tags                                            = merge(var.tags, { Name = "${local.name}-${each.key}" })
}

resource "aws_ec2_transit_gateway_route_table_association" "this" {
  for_each = var.attachments

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this[each.value.route_table].id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "this" {
  for_each = local.propagations

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.value.attachment].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this[each.value.route_table].id
}

resource "aws_ec2_transit_gateway_route" "this" {
  for_each = { for r in var.static_routes : "${r.route_table}/${r.cidr}" => r }

  destination_cidr_block         = each.value.cidr
  blackhole                      = each.value.attachment == null
  transit_gateway_attachment_id  = each.value.attachment == null ? null : aws_ec2_transit_gateway_vpc_attachment.this[each.value.attachment].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this[each.value.route_table].id
}

resource "aws_ram_resource_share" "this" {
  count = length(var.ram_principals) == 0 ? 0 : 1

  name                      = local.name
  allow_external_principals = false
  tags                      = merge(var.tags, { Name = local.name })
}

resource "aws_ram_resource_association" "this" {
  count = length(aws_ram_resource_share.this)

  resource_arn       = aws_ec2_transit_gateway.this.arn
  resource_share_arn = aws_ram_resource_share.this[0].arn
}

resource "aws_ram_principal_association" "this" {
  for_each = toset(var.ram_principals)

  principal          = each.key
  resource_share_arn = aws_ram_resource_share.this[0].arn
}
