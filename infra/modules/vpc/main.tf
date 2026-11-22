locals {
  region_short = join("", [split("-", var.region)[0], substr(split("-", var.region)[1], 0, 1), split("-", var.region)[2]])
  name         = "pay-${var.environment}-${local.region_short}-${var.component}"
  tiers        = ["public", "private", "data"]

  subnets = merge([
    for t in local.tiers : {
      for i, cidr in var.subnet_cidrs[t] : "${t}-${i}" => { tier = t, cidr = cidr, az = var.azs[i] }
    }
  ]...)

  has_public = length(var.subnet_cidrs.public) > 0
  az_index   = { for i, az in var.azs : tostring(i) => az }
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(var.tags, { Name = local.name })
}

# No rules at all: every workload attaches its own security group.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${local.name}-default-deny" })
}

resource "aws_subnet" "this" {
  for_each = local.subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false
  tags                    = merge(var.tags, { Name = "${local.name}-${each.key}", tier = each.value.tier })
}

resource "aws_internet_gateway" "this" {
  count = var.enable_internet_gateway && local.has_public ? 1 : 0

  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = local.name })
}

resource "aws_route_table" "public" {
  count = local.has_public ? 1 : 0

  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${local.name}-public" })
}

resource "aws_route" "public_internet" {
  count = length(aws_internet_gateway.this)

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_route_table" "private" {
  for_each = local.az_index

  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${local.name}-private-${each.key}" })
}

resource "aws_route" "private_egress" {
  for_each = var.enable_egress_route ? local.az_index : {}

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = var.egress_transit_gateway_id
}

# The data tier has no default route: databases never reach out.
resource "aws_route_table" "data" {
  for_each = local.az_index

  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${local.name}-data-${each.key}" })
}

resource "aws_route_table_association" "public" {
  for_each = local.has_public ? { for k, v in local.subnets : k => v if v.tier == "public" } : {}

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_route_table_association" "private" {
  for_each = { for k, v in local.subnets : k => v if v.tier == "private" }

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.private[element(split("-", each.key), 1)].id
}

resource "aws_route_table_association" "data" {
  for_each = { for k, v in local.subnets : k => v if v.tier == "data" }

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.data[element(split("-", each.key), 1)].id
}

resource "aws_vpc_endpoint" "gateway" {
  for_each = toset(var.gateway_endpoint_services)

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat([for rt in aws_route_table.private : rt.id], [for rt in aws_route_table.data : rt.id])
  tags              = merge(var.tags, { Name = "${local.name}-${each.key}" })
}

resource "aws_security_group" "endpoints" {
  name        = "${local.name}-endpoints"
  description = "HTTPS from the VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id
  tags        = merge(var.tags, { Name = "${local.name}-endpoints" })
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  security_group_id = aws_security_group.endpoints.id
  cidr_ipv4         = var.cidr_block
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS from the VPC"
  tags              = var.tags
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.interface_endpoint_services)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for i in range(3) : aws_subnet.this["private-${i}"].id]
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true
  tags                = merge(var.tags, { Name = "${local.name}-${each.key}" })
}

resource "aws_flow_log" "this" {
  vpc_id                   = aws_vpc.this.id
  traffic_type             = "ALL"
  log_destination_type     = "s3"
  log_destination          = var.flow_logs_bucket_arn
  max_aggregation_interval = 60

  destination_options {
    file_format        = "parquet"
    per_hour_partition = true
  }

  tags = merge(var.tags, { Name = local.name })
}
