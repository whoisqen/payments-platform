locals {
  region_short = join("", [split("-", var.region)[0], substr(split("-", var.region)[1], 0, 1), split("-", var.region)[2]])
  name         = "pay-${var.environment}-${local.region_short}-${var.component}"
  az_index     = { for i, id in var.nat_subnet_ids : tostring(i) => id }
}

resource "aws_networkfirewall_rule_group" "psp_allowlist" {
  name        = "${local.name}-psp-allowlist"
  description = "Egress allowlist of PSP domains (SNI and HTTP host)"
  type        = "STATEFUL"
  capacity    = var.rule_group_capacity

  rule_group {
    rules_source {
      rules_source_list {
        generated_rules_type = "ALLOWLIST"
        target_types         = ["HTTP_HOST", "TLS_SNI"]
        targets              = var.psp_domains
      }
    }

    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }

  tags = merge(var.tags, { Name = "${local.name}-psp-allowlist" })
}

resource "aws_networkfirewall_firewall_policy" "this" {
  name = local.name

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]
    stateful_default_actions           = ["aws:drop_established", "aws:alert_established"]

    stateful_engine_options {
      rule_order = "STRICT_ORDER"
    }

    stateful_rule_group_reference {
      priority     = 1
      resource_arn = aws_networkfirewall_rule_group.psp_allowlist.arn
    }
  }

  tags = merge(var.tags, { Name = local.name })
}

resource "aws_networkfirewall_firewall" "this" {
  name                = local.name
  firewall_policy_arn = aws_networkfirewall_firewall_policy.this.arn
  vpc_id              = var.vpc_id
  delete_protection   = var.delete_protection

  dynamic "subnet_mapping" {
    for_each = var.firewall_subnet_ids

    content {
      subnet_id = subnet_mapping.value
    }
  }

  tags = merge(var.tags, { Name = local.name })
}

resource "aws_networkfirewall_logging_configuration" "this" {
  count = var.enable_logging ? 1 : 0

  firewall_arn = aws_networkfirewall_firewall.this.arn

  logging_configuration {
    dynamic "log_destination_config" {
      for_each = ["ALERT", "FLOW"]

      content {
        log_type             = log_destination_config.value
        log_destination_type = "S3"
        log_destination = {
          bucketName = var.log_bucket_name
          prefix     = "${local.name}/${lower(log_destination_config.value)}"
        }
      }
    }
  }
}

# The elastic IPs are registered with every PSP, so they must outlive the gateways.
resource "aws_eip" "nat" {
  for_each = local.az_index

  domain = "vpc"
  tags   = merge(var.tags, { Name = "${local.name}-nat-${each.key}" })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_nat_gateway" "this" {
  for_each = local.az_index

  allocation_id     = aws_eip.nat[each.key].id
  subnet_id         = each.value
  connectivity_type = "public"
  tags              = merge(var.tags, { Name = "${local.name}-${each.key}" })
}
