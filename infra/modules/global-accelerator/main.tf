locals {
  name      = "${var.name_prefix}-${var.environment}-glob-${var.component}"
  endpoints = { for r, g in var.endpoint_groups : r => distinct(concat(g.endpoint_arns, length(g.endpoint_lb_tags) == 0 ? [] : tolist(data.aws_lbs.edge[r].arns))) }
}

# The edge ingress load balancer belongs to Kubernetes, so it is found by tag in its region; a region without it yet has no endpoint.
data "aws_lbs" "edge" {
  for_each = { for r, g in var.endpoint_groups : r => g if length(g.endpoint_lb_tags) > 0 }

  region = each.key
  tags   = each.value.endpoint_lb_tags
}

resource "aws_globalaccelerator_accelerator" "this" {
  name            = local.name
  ip_address_type = "IPV4"
  enabled         = true

  dynamic "attributes" {
    for_each = var.flow_logs_bucket == null ? [] : [var.flow_logs_bucket]

    content {
      flow_logs_enabled   = true
      flow_logs_s3_bucket = attributes.value
      flow_logs_s3_prefix = "${local.name}/"
    }
  }

  tags = merge(var.tags, { Name = local.name })
}

resource "aws_globalaccelerator_listener" "this" {
  accelerator_arn = aws_globalaccelerator_accelerator.this.id
  protocol        = "TCP"
  client_affinity = "NONE"

  dynamic "port_range" {
    for_each = var.listener_ports

    content {
      from_port = port_range.value
      to_port   = port_range.value
    }
  }
}

# A recovery group stays registered with weight 0 and dial 0 so the switch only flips `active`.
resource "aws_globalaccelerator_endpoint_group" "this" {
  for_each = var.endpoint_groups

  listener_arn                  = aws_globalaccelerator_listener.this.id
  endpoint_group_region         = each.key
  traffic_dial_percentage       = each.value.active ? 100 : 0
  health_check_protocol         = each.value.health_check_protocol
  health_check_port             = each.value.health_check_port
  health_check_path             = each.value.health_check_protocol == "TCP" ? null : each.value.health_check_path
  health_check_interval_seconds = 10
  threshold_count               = 3

  dynamic "endpoint_configuration" {
    for_each = local.endpoints[each.key]

    content {
      endpoint_id                    = endpoint_configuration.value
      weight                         = each.value.active ? 128 : 0
      client_ip_preservation_enabled = true
    }
  }
}
