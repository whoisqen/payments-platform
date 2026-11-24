mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "222222222222" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_wafv2_web_acl" {
    defaults = { arn = "arn:aws:wafv2:us-east-1:222222222222:global/webacl/mock/00000000-0000-0000-0000-000000000000" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:us-east-1:222222222222:log-group:aws-waf-logs-mock" }
  }
}

variables {
  name_prefix = "pay"
  environment = "dev"
  kms_key_arn = "arn:aws:kms:us-east-1:222222222222:key/mrk-logs"
  tags = {
    team          = "platform"
    owner         = "platform@example.com"
    "pci-scope"   = "connected"
    "data-class"  = "public"
    "backup-tier" = "none"
  }
}

run "count_mode_has_groups_rate_rules_and_logging" {
  command = apply

  assert {
    condition     = alltrue([for k in ["common", "bad-inputs", "sqli", "ip-reputation"] : alltrue([for a in aws_wafv2_web_acl.this : contains([for r in a.rule : r.name], "managed-${k}")])])
    error_message = "every ACL carries the four managed groups"
  }

  assert {
    condition     = alltrue([for a in aws_wafv2_web_acl.this : alltrue([for n in ["rate-ip", "rate-api-key", "rate-merchant"] : contains([for r in a.rule : r.name], n)])])
    error_message = "every ACL has the IP, API key and merchant rate rules"
  }

  assert {
    condition     = contains([for r in aws_wafv2_web_acl.this["panel"].rule : r.name], "managed-bot-control") && contains([for r in aws_wafv2_web_acl.this["panel"].rule : r.name], "managed-atp") && contains([for r in aws_wafv2_web_acl.this["panel"].rule : r.name], "rate-auth")
    error_message = "the panel has Bot Control, ATP and the auth rate rule"
  }

  assert {
    condition     = !contains([for r in aws_wafv2_web_acl.this["sdk"].rule : r.name], "managed-bot-control") && !contains([for r in aws_wafv2_web_acl.this["sdk"].rule : r.name], "managed-atp") && !contains([for r in aws_wafv2_web_acl.this["sdk"].rule : r.name], "rate-auth")
    error_message = "the SDK has neither Bot Control, ATP nor the auth rate rule"
  }

  assert {
    condition     = alltrue([for a in aws_wafv2_web_acl.this : alltrue([for r in a.rule : length(r.override_action) == 0 || length(r.override_action[0].count) == 1])]) && alltrue([for a in aws_wafv2_web_acl.this : alltrue([for r in a.rule : length(r.action) == 0 || length(r.action[0].count) == 1])])
    error_message = "count mode counts every managed group and rate rule"
  }

  assert {
    condition     = alltrue([for a in aws_wafv2_web_acl.this : a.scope == "CLOUDFRONT" && a.visibility_config[0].cloudwatch_metrics_enabled && a.visibility_config[0].sampled_requests_enabled])
    error_message = "CloudFront scope with metrics and sampled requests"
  }

  assert {
    condition     = alltrue([for l in aws_wafv2_web_acl_logging_configuration.this : toset([for f in l.redacted_fields : f.single_header[0].name]) == toset(["authorization", "cookie", "x-api-key"])])
    error_message = "authorization, cookie and x-api-key are redacted"
  }

  assert {
    condition     = alltrue([for g in aws_cloudwatch_log_group.waf : startswith(g.name, "aws-waf-logs-") && g.retention_in_days == 30 && g.kms_key_id == var.kms_key_arn])
    error_message = "log groups are named for WAF, kept 30 days and encrypted"
  }
}

run "block_mode_enforces_and_answers_429" {
  command = apply

  variables {
    mode = "block"
  }

  assert {
    condition     = alltrue([for a in aws_wafv2_web_acl.this : alltrue([for r in a.rule : length(r.override_action) == 0 || length(r.override_action[0].none) == 1])])
    error_message = "block mode lets the managed groups act"
  }

  assert {
    condition     = alltrue([for a in aws_wafv2_web_acl.this : alltrue([for r in a.rule : length(r.action) == 0 || (length(r.action[0].block) == 1 && r.action[0].block[0].custom_response[0].response_code == 429 && contains([for h in r.action[0].block[0].custom_response[0].response_header : h.name], "Retry-After"))])])
    error_message = "rate rules block with 429 and Retry-After"
  }
}

run "regional_scope_in_cloudfront_region_is_rejected" {
  command = plan

  variables {
    scope = "REGIONAL"
  }

  expect_failures = [aws_wafv2_web_acl.this]
}

run "mode_is_validated" {
  command = plan

  variables {
    mode = "log"
  }

  expect_failures = [var.mode]
}
