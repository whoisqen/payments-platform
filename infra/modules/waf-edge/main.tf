data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name       = "${var.name_prefix}-${var.environment}-glob-waf"
  block_mode = var.mode == "block"

  managed_groups = {
    common        = { name = "AWSManagedRulesCommonRuleSet", priority = 10 }
    bad-inputs    = { name = "AWSManagedRulesKnownBadInputsRuleSet", priority = 20 }
    sqli          = { name = "AWSManagedRulesSQLiRuleSet", priority = 30 }
    ip-reputation = { name = "AWSManagedRulesAmazonIpReputationList", priority = 40 }
  }
}

resource "aws_wafv2_web_acl" "this" {
  for_each = var.entries

  name        = "${local.name}-${each.key}"
  description = "Public entry ${each.key}"
  scope       = var.scope

  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = local.managed_groups

    content {
      name     = "managed-${rule.key}"
      priority = rule.value.priority

      override_action {
        dynamic "count" {
          for_each = local.block_mode ? [] : [1]
          content {}
        }
        dynamic "none" {
          for_each = local.block_mode ? [1] : []
          content {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value.name
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        sampled_requests_enabled   = true
        metric_name                = "${local.name}-${each.key}-managed-${rule.key}"
      }
    }
  }

  dynamic "rule" {
    for_each = each.value.bot_control ? [1] : []

    content {
      name     = "managed-bot-control"
      priority = 50

      override_action {
        dynamic "count" {
          for_each = local.block_mode ? [] : [1]
          content {}
        }
        dynamic "none" {
          for_each = local.block_mode ? [1] : []
          content {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesBotControlRuleSet"
          vendor_name = "AWS"

          managed_rule_group_configs {
            aws_managed_rules_bot_control_rule_set {
              inspection_level = "COMMON"
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        sampled_requests_enabled   = true
        metric_name                = "${local.name}-${each.key}-managed-bot-control"
      }
    }
  }

  # ATP is billed per inspected request, so it sees the login path only.
  dynamic "rule" {
    for_each = each.value.atp ? [1] : []

    content {
      name     = "managed-atp"
      priority = 60

      override_action {
        dynamic "count" {
          for_each = local.block_mode ? [] : [1]
          content {}
        }
        dynamic "none" {
          for_each = local.block_mode ? [1] : []
          content {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesATPRuleSet"
          vendor_name = "AWS"

          managed_rule_group_configs {
            aws_managed_rules_atp_rule_set {
              login_path = each.value.login_path

              request_inspection {
                payload_type = "JSON"

                username_field {
                  identifier = each.value.username_field
                }

                password_field {
                  identifier = each.value.password_field
                }
              }
            }
          }

          scope_down_statement {
            byte_match_statement {
              search_string         = each.value.login_path
              positional_constraint = "STARTS_WITH"

              field_to_match {
                uri_path {}
              }

              text_transformation {
                priority = 0
                type     = "NONE"
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        sampled_requests_enabled   = true
        metric_name                = "${local.name}-${each.key}-managed-atp"
      }
    }
  }

  rule {
    name     = "rate-ip"
    priority = 100

    action {
      dynamic "count" {
        for_each = local.block_mode ? [] : [1]
        content {}
      }
      dynamic "block" {
        for_each = local.block_mode ? [1] : []
        content {
          custom_response {
            response_code = 429

            response_header {
              name  = "Retry-After"
              value = tostring(var.evaluation_window_sec)
            }
          }
        }
      }
    }

    statement {
      rate_based_statement {
        limit                 = var.rate_limit_ip
        aggregate_key_type    = "IP"
        evaluation_window_sec = var.evaluation_window_sec
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "${local.name}-${each.key}-rate-ip"
    }
  }

  dynamic "rule" {
    for_each = { api-key = { priority = 110, header = var.api_key_header }, merchant = { priority = 120, header = var.merchant_header } }

    content {
      name     = "rate-${rule.key}"
      priority = rule.value.priority

      action {
        dynamic "count" {
          for_each = local.block_mode ? [] : [1]
          content {}
        }
        dynamic "block" {
          for_each = local.block_mode ? [1] : []
          content {
            custom_response {
              response_code = 429

              response_header {
                name  = "Retry-After"
                value = tostring(var.evaluation_window_sec)
              }
            }
          }
        }
      }

      statement {
        rate_based_statement {
          limit                 = var.rate_limit_api_key
          aggregate_key_type    = "CUSTOM_KEYS"
          evaluation_window_sec = var.evaluation_window_sec

          custom_key {
            header {
              name = rule.value.header

              text_transformation {
                priority = 0
                type     = "NONE"
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        sampled_requests_enabled   = true
        metric_name                = "${local.name}-${each.key}-rate-${rule.key}"
      }
    }
  }

  dynamic "rule" {
    for_each = length(each.value.auth_paths) > 0 ? [1] : []

    content {
      name     = "rate-auth"
      priority = 90

      action {
        dynamic "count" {
          for_each = local.block_mode ? [] : [1]
          content {}
        }
        dynamic "block" {
          for_each = local.block_mode ? [1] : []
          content {
            custom_response {
              response_code = 429

              response_header {
                name  = "Retry-After"
                value = tostring(var.evaluation_window_sec)
              }
            }
          }
        }
      }

      statement {
        rate_based_statement {
          limit                 = var.rate_limit_auth
          aggregate_key_type    = "IP"
          evaluation_window_sec = var.evaluation_window_sec

          scope_down_statement {
            dynamic "or_statement" {
              for_each = length(each.value.auth_paths) > 1 ? [1] : []

              content {
                dynamic "statement" {
                  for_each = each.value.auth_paths

                  content {
                    byte_match_statement {
                      search_string         = statement.value
                      positional_constraint = "STARTS_WITH"

                      field_to_match {
                        uri_path {}
                      }

                      text_transformation {
                        priority = 0
                        type     = "NONE"
                      }
                    }
                  }
                }
              }
            }

            dynamic "byte_match_statement" {
              for_each = length(each.value.auth_paths) == 1 ? each.value.auth_paths : []

              content {
                search_string         = byte_match_statement.value
                positional_constraint = "STARTS_WITH"

                field_to_match {
                  uri_path {}
                }

                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        sampled_requests_enabled   = true
        metric_name                = "${local.name}-${each.key}-rate-auth"
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    sampled_requests_enabled   = true
    metric_name                = "${local.name}-${each.key}"
  }

  lifecycle {
    precondition {
      condition     = (var.scope == "CLOUDFRONT") == (data.aws_region.current.region == "us-east-1")
      error_message = "A CLOUDFRONT web ACL exists only in us-east-1, and a REGIONAL one belongs in the Region of its load balancer; run the stack in the matching Region."
    }
  }

  tags = merge(var.tags, { Name = "${local.name}-${each.key}" })
}

resource "aws_cloudwatch_log_group" "waf" {
  for_each = var.entries

  name              = "aws-waf-logs-${local.name}-${each.key}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, { Name = "aws-waf-logs-${local.name}-${each.key}" })
}

data "aws_iam_policy_document" "delivery" {
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [for g in aws_cloudwatch_log_group.waf : "${g.arn}:*"]

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "delivery" {
  policy_name     = "${local.name}-delivery"
  policy_document = data.aws_iam_policy_document.delivery.json
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  for_each = var.entries

  resource_arn            = aws_wafv2_web_acl.this[each.key].arn
  log_destination_configs = [aws_cloudwatch_log_group.waf[each.key].arn]

  dynamic "redacted_fields" {
    for_each = toset(var.redacted_headers)

    content {
      single_header {
        name = redacted_fields.value
      }
    }
  }

  depends_on = [aws_cloudwatch_log_resource_policy.delivery]
}
