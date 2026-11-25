mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:us-east-1:111111111111:log-group:/aws/vendedlogs/cloudfront/pay-prod-glob-panel" }
  }
  mock_resource "aws_cloudwatch_log_delivery_destination" {
    defaults = { arn = "arn:aws:logs:us-east-1:111111111111:delivery-destination:pay-prod-glob-panel-access" }
  }
  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      arn            = "arn:aws:cloudfront::111111111111:distribution/E000000000000"
      domain_name    = "d000000000000.cloudfront.net"
      hosted_zone_id = "Z2FDTNDATAQYW2"
    }
  }
  mock_data "aws_lb" {
    defaults = {
      arn      = "arn:aws:elasticloadbalancing:eu-central-1:111111111111:loadbalancer/net/k8s-panel-gw/0123456789abcdef"
      dns_name = "k8s-panel-gw-0123456789.elb.eu-central-1.amazonaws.com"
      zone_id  = "Z3F0SRJ5LGBH90"
    }
  }
}

override_resource {
  target = aws_acm_certificate.this["panel"]
  values = {
    arn = "arn:aws:acm:us-east-1:111111111111:certificate/00000000-0000-0000-0000-000000000001"
    domain_validation_options = [
      { domain_name = "panel.pay.example.com", resource_record_name = "_a.panel.pay.example.com.", resource_record_type = "CNAME", resource_record_value = "_b.acm-validations.aws." },
    ]
  }
}

override_resource {
  target = aws_acm_certificate.this["sdk"]
  values = {
    arn = "arn:aws:acm:us-east-1:111111111111:certificate/00000000-0000-0000-0000-000000000002"
    domain_validation_options = [
      { domain_name = "sdk.pay.example.com", resource_record_name = "_c.sdk.pay.example.com.", resource_record_type = "CNAME", resource_record_value = "_d.acm-validations.aws." },
    ]
  }
}

variables {
  name_prefix = "pay"
  environment = "prod"
  zone_name   = "pay.example.com"
  zone_id     = "Z0000000000000000000"
  web_acl_arns = {
    panel = "arn:aws:wafv2:us-east-1:111111111111:global/webacl/pay-prod-glob-waf-panel/00000000-0000-0000-0000-000000000001"
    sdk   = "arn:aws:wafv2:us-east-1:111111111111:global/webacl/pay-prod-glob-waf-sdk/00000000-0000-0000-0000-000000000002"
  }
  kms_key_arn = "arn:aws:kms:us-east-1:111111111111:key/mrk-logs"
  tags = {
    team          = "platform"
    owner         = "platform@example.com"
    "pci-scope"   = "connected"
    "data-class"  = "public"
    "backup-tier" = "none"
  }
}

run "first_step_has_certificates_and_policies_only" {
  command = apply

  assert {
    condition     = length(aws_acm_certificate.this) == 2 && aws_acm_certificate.this["panel"].domain_name == "panel.pay.example.com" && aws_acm_certificate.this["sdk"].validation_method == "DNS"
    error_message = "one DNS-validated certificate per entry"
  }
  assert {
    condition     = length(aws_route53_record.validation) == 2 && aws_route53_record.validation["panel"].zone_id == var.zone_id
    error_message = "validation records in the public zone"
  }
  assert {
    condition     = length(data.aws_lb.gateway) == 0 && length(aws_cloudfront_vpc_origin.gateway) == 0 && length(aws_cloudfront_distribution.this) == 0 && length(aws_route53_record.alias) == 0
    error_message = "no NLB lookup, origin, distribution or record in the first step"
  }
  assert {
    condition     = length(aws_cloudwatch_log_delivery.access) == 0 && length(aws_cloudwatch_log_group.access) == 1 && aws_cloudwatch_log_group.access[0].kms_key_id == var.kms_key_arn
    error_message = "encrypted log group ready, no delivery yet"
  }
}

run "second_step_builds_the_entries" {
  command = apply

  variables {
    nlb_lookup_enabled = true
    nlb_stack_tag      = "istio-ingress/panel-istio"
    geo_restriction    = { type = "blacklist", locations = ["KP", "IR"] }
  }

  assert {
    condition     = data.aws_lb.gateway[0].tags["service.k8s.aws/stack"] == "istio-ingress/panel-istio" && data.aws_lb.gateway[0].region == "eu-central-1"
    error_message = "NLB found by the stack tag in the working region"
  }
  assert {
    condition = alltrue([
      aws_cloudfront_vpc_origin.gateway[0].vpc_origin_endpoint_config[0].origin_protocol_policy == "https-only",
      aws_cloudfront_vpc_origin.gateway[0].vpc_origin_endpoint_config[0].origin_ssl_protocols[0].items == toset(["TLSv1.2"]),
      aws_cloudfront_vpc_origin.gateway[0].vpc_origin_endpoint_config[0].arn == data.aws_lb.gateway[0].arn,
    ])
    error_message = "VPC origin to the NLB over HTTPS with TLS 1.2"
  }
  assert {
    condition = alltrue([for k, d in aws_cloudfront_distribution.this : alltrue([
      d.web_acl_id == var.web_acl_arns[k],
      d.http_version == "http2and3",
      d.is_ipv6_enabled,
      d.viewer_certificate[0].minimum_protocol_version == "TLSv1.2_2021",
      d.viewer_certificate[0].ssl_support_method == "sni-only",
      d.restrictions[0].geo_restriction[0].restriction_type == "blacklist",
    ])])
    error_message = "every distribution has its ACL, HTTP/2 and 3, TLSv1.2_2021 and the geo restriction"
  }
  assert {
    condition     = aws_cloudfront_distribution.this["panel"].default_cache_behavior[0].cache_policy_id == aws_cloudfront_cache_policy.api.id && aws_cloudfront_distribution.this["panel"].ordered_cache_behavior[0].path_pattern == "/api/*" && aws_cloudfront_distribution.this["panel"].ordered_cache_behavior[0].cache_policy_id == aws_cloudfront_cache_policy.api.id
    error_message = "API path and default are not cached"
  }
  assert {
    condition     = aws_cloudfront_distribution.this["panel"].ordered_cache_behavior[1].cache_policy_id == aws_cloudfront_cache_policy.static.id && aws_cloudfront_cache_policy.static.max_ttl <= 3600 && aws_cloudfront_cache_policy.api.default_ttl == 0
    error_message = "static assets have a short TTL"
  }
  assert {
    condition     = contains(aws_cloudfront_origin_request_policy.dynamic["panel"].headers_config[0].headers[0].items, "Host") && contains(aws_cloudfront_cache_policy.api.parameters_in_cache_key_and_forwarded_to_origin[0].headers_config[0].headers[0].items, "Authorization")
    error_message = "Host through the origin request policy, Authorization through the cache key"
  }
  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this["panel"].security_headers_config[0].frame_options) == 1 && length(aws_cloudfront_response_headers_policy.this["sdk"].security_headers_config[0].frame_options) == 0 && aws_cloudfront_response_headers_policy.this["panel"].security_headers_config[0].strict_transport_security[0].access_control_max_age_sec >= 31536000
    error_message = "HSTS everywhere, frame deny on the panel only"
  }
  assert {
    condition     = length(aws_route53_record.alias) == 4 && aws_route53_record.alias["sdk/AAAA"].name == "sdk.pay.example.com"
    error_message = "A and AAAA alias per entry"
  }
  assert {
    condition     = length(aws_cloudwatch_log_delivery.access) == 2 && !contains(aws_cloudwatch_log_delivery.access["panel"].record_fields, "cs(Cookie)")
    error_message = "one log delivery per distribution without cookies"
  }
}

run "s3_log_destination" {
  command = plan

  variables {
    log_bucket_arn = "arn:aws:s3:::pay-prod-log-archive-cdn-logs"
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.access) == 0 && aws_cloudwatch_log_delivery_destination.access.output_format == "parquet"
    error_message = "S3 destination replaces the log group"
  }
}

run "second_step_needs_the_stack_tag" {
  command = plan

  variables {
    nlb_lookup_enabled = true
  }

  expect_failures = [data.aws_lb.gateway]
}

run "every_entry_needs_an_acl" {
  command = plan

  variables {
    web_acl_arns = { panel = "arn:aws:wafv2:us-east-1:111111111111:global/webacl/pay-prod-glob-waf-panel/00000000-0000-0000-0000-000000000001" }
  }

  expect_failures = [var.web_acl_arns]
}

run "regional_acl_rejected" {
  command = plan

  variables {
    web_acl_arns = {
      panel = "arn:aws:wafv2:eu-central-1:111111111111:regional/webacl/x/1"
      sdk   = "arn:aws:wafv2:eu-central-1:111111111111:regional/webacl/y/2"
    }
  }

  expect_failures = [var.web_acl_arns]
}

run "query_string_logging_rejected" {
  command = plan

  variables {
    log_record_fields = ["date", "cs-uri-query"]
  }

  expect_failures = [var.log_record_fields]
}
