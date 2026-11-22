locals {
  region_short = join("", [split("-", var.region)[0], substr(split("-", var.region)[1], 0, 1), split("-", var.region)[2]])
  name         = "pay-${var.environment}-${local.region_short}-${var.component}"

  workload_sources = concat(
    [for i, id in var.client_security_group_ids : { key = "sg-${i}", sg = id, cidr = null }],
    [for i, c in var.client_cidr_blocks : { key = "cidr-${i}", sg = null, cidr = c }],
  )

  ingress = merge([for s, cfg in var.stores : {
    for src in(cfg.clients == "workload" ? local.workload_sources : [{ key = "store", sg = aws_security_group.this[cfg.clients].id, cidr = null }]) :
    "${s}/${src.key}" => { store = s, port = cfg.port, sg = src.sg, cidr = src.cidr }
  }]...)

  store_clients = { for s, cfg in var.stores : s => cfg.clients if cfg.clients != "workload" }
}

resource "aws_security_group" "this" {
  for_each = var.stores

  name        = "${local.name}-${each.key}"
  description = "${each.key} of ${var.component}; ingress only from the listed clients."
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${local.name}-${each.key}" })
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = local.ingress

  security_group_id            = aws_security_group.this[each.value.store].id
  referenced_security_group_id = each.value.sg
  cidr_ipv4                    = each.value.cidr
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  description                  = "Client access to ${each.value.store}"
}

# A store that fronts another one (the proxy in front of Aurora) may open connections to it and nowhere else.
resource "aws_vpc_security_group_egress_rule" "to_store" {
  for_each = local.store_clients

  security_group_id            = aws_security_group.this[each.value].id
  referenced_security_group_id = aws_security_group.this[each.key].id
  ip_protocol                  = "tcp"
  from_port                    = var.stores[each.key].port
  to_port                      = var.stores[each.key].port
  description                  = "To ${each.key}"
}

resource "aws_db_subnet_group" "this" {
  name        = local.name
  description = "Data subnets of ${var.component}"
  subnet_ids  = var.data_subnet_ids
  tags        = var.tags
}
