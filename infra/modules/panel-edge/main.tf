data "aws_caller_identity" "current" {}

locals {
  name      = "${var.name_prefix}-${var.environment}-glob-panel"
  step_two  = var.nlb_lookup_enabled
  to_s3     = var.log_bucket_arn != null
  origin_id = "gateway"

  fqdns = { for k, e in var.entries : k => "${coalesce(e.subdomain, k)}.${var.zone_name}" }

  # Keys come from configuration, so for_each is known at plan time.
  validation_options = {
    for k, fqdn in local.fqdns : k => one([
      for d in aws_acm_certificate.this[k].domain_validation_options : d if d.domain_name == fqdn
    ])
  }

  aliases = merge([for k in keys(var.entries) : { "${k}/A" = k, "${k}/AAAA" = k }]...)
}

# ---------------------------------------------------------------------------
# Certificates (us-east-1, the provider of the stack) validated in the public zone
# ---------------------------------------------------------------------------

resource "aws_acm_certificate" "this" {
  for_each = local.fqdns

  domain_name       = each.value
  validation_method = "DNS"
  key_algorithm     = "EC_prime256v1"
  tags              = merge(var.tags, { Name = "${local.name}-${each.key}" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "validation" {
  for_each = local.validation_options

  zone_id         = var.zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  for_each = local.fqdns

  certificate_arn         = aws_acm_certificate.this[each.key].arn
  validation_record_fqdns = [aws_route53_record.validation[each.key].fqdn]
}

# ---------------------------------------------------------------------------
# Cache, origin request and response headers policies
# ---------------------------------------------------------------------------

# max_ttl 1 instead of CachingDisabled: only a cache policy can forward Authorization, and all-zero TTLs forbid headers; the Gateway must answer no-store on these paths.
resource "aws_cloudfront_cache_policy" "api" {
  name        = "${local.name}-api"
  comment     = "Dynamic paths: not cached, Authorization forwarded"
  min_ttl     = 0
  default_ttl = 0
  max_ttl     = 1

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true

    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["Authorization"]
      }
    }
    cookies_config {
      cookie_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

resource "aws_cloudfront_cache_policy" "static" {
  name        = "${local.name}-static"
  comment     = "Static panel and SDK assets, short TTL"
  min_ttl     = var.static_ttl.min
  default_ttl = var.static_ttl.default
  max_ttl     = var.static_ttl.max

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true

    headers_config {
      header_behavior = "none"
    }
    cookies_config {
      cookie_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

resource "aws_cloudfront_origin_request_policy" "dynamic" {
  for_each = var.entries

  name    = "${local.name}-${each.key}-dynamic"
  comment = "Only the headers the Gateway and the application read"

  headers_config {
    header_behavior = "whitelist"
    headers {
      items = var.origin_headers
    }
  }

  cookies_config {
    cookie_behavior = length(each.value.forward_cookies) > 0 ? "whitelist" : "none"
    dynamic "cookies" {
      for_each = length(each.value.forward_cookies) > 0 ? [1] : []
      content {
        items = each.value.forward_cookies
      }
    }
  }

  query_strings_config {
    query_string_behavior = "all"
  }
}

# Host only: the HTTPRoute matches on it and CloudFront checks the origin certificate against it.
resource "aws_cloudfront_origin_request_policy" "static" {
  name    = "${local.name}-static"
  comment = "Static assets: Host only"

  headers_config {
    header_behavior = "whitelist"
    headers {
      items = ["Host"]
    }
  }
  cookies_config {
    cookie_behavior = "none"
  }
  query_strings_config {
    query_string_behavior = "none"
  }
}

resource "aws_cloudfront_response_headers_policy" "this" {
  for_each = var.entries

  name    = "${local.name}-${each.key}-security"
  comment = "Security headers of the ${each.key} entry"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = var.hsts.max_age_sec
      include_subdomains         = var.hsts.include_subdomains
      preload                    = var.hsts.preload
      override                   = true
    }

    content_type_options {
      override = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }

    content_security_policy {
      content_security_policy = each.value.content_security_policy
      override                = true
    }

    dynamic "frame_options" {
      for_each = each.value.frame_deny ? [1] : []
      content {
        frame_option = "DENY"
        override     = true
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Second step: VPC origin to the internal NLB of the Gateway, distributions, alias records
# ---------------------------------------------------------------------------

# The NLB belongs to the load balancer controller, which builds it from the Gateway; it exists only after the Gateway syncs.
data "aws_lb" "gateway" {
  count  = local.step_two ? 1 : 0
  region = var.origin_region

  tags = merge(
    { "service.k8s.aws/stack" = var.nlb_stack_tag },
    var.nlb_cluster_name == null ? {} : { "elbv2.k8s.aws/cluster" = var.nlb_cluster_name },
  )

  lifecycle {
    precondition {
      condition     = var.nlb_stack_tag != null
      error_message = "nlb_stack_tag is required when nlb_lookup_enabled is true."
    }
  }
}

# The NLB stays internal and admits only the CloudFront VPC origin ENIs, so no shared-secret origin header is needed.
resource "aws_cloudfront_vpc_origin" "gateway" {
  count = local.step_two ? 1 : 0

  vpc_origin_endpoint_config {
    name                   = "${local.name}-gateway"
    arn                    = data.aws_lb.gateway[0].arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "https-only"

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }

  tags = merge(var.tags, { Name = "${local.name}-gateway" })
}

resource "aws_cloudfront_distribution" "this" {
  for_each = local.step_two ? var.entries : {}

  enabled         = true
  comment         = "${local.name}-${each.key}"
  aliases         = [local.fqdns[each.key]]
  http_version    = "http2and3"
  is_ipv6_enabled = true
  price_class     = var.price_class
  web_acl_id      = var.web_acl_arns[each.key]

  origin {
    origin_id   = local.origin_id
    domain_name = data.aws_lb.gateway[0].dns_name

    vpc_origin_config {
      vpc_origin_id            = aws_cloudfront_vpc_origin.gateway[0].id
      origin_read_timeout      = var.origin_read_timeout
      origin_keepalive_timeout = 5
    }
  }

  default_cache_behavior {
    target_origin_id           = local.origin_id
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = aws_cloudfront_cache_policy.api.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.dynamic[each.key].id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.this[each.key].id
  }

  dynamic "ordered_cache_behavior" {
    for_each = each.value.api_paths

    content {
      path_pattern               = ordered_cache_behavior.value
      target_origin_id           = local.origin_id
      viewer_protocol_policy     = "https-only"
      allowed_methods            = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
      cached_methods             = ["GET", "HEAD"]
      compress                   = true
      cache_policy_id            = aws_cloudfront_cache_policy.api.id
      origin_request_policy_id   = aws_cloudfront_origin_request_policy.dynamic[each.key].id
      response_headers_policy_id = aws_cloudfront_response_headers_policy.this[each.key].id
    }
  }

  dynamic "ordered_cache_behavior" {
    for_each = each.value.static_paths

    content {
      path_pattern               = ordered_cache_behavior.value
      target_origin_id           = local.origin_id
      viewer_protocol_policy     = "redirect-to-https"
      allowed_methods            = ["GET", "HEAD", "OPTIONS"]
      cached_methods             = ["GET", "HEAD"]
      compress                   = true
      cache_policy_id            = aws_cloudfront_cache_policy.static.id
      origin_request_policy_id   = aws_cloudfront_origin_request_policy.static.id
      response_headers_policy_id = aws_cloudfront_response_headers_policy.this[each.key].id
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.this[each.key].certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = var.geo_restriction.type
      locations        = var.geo_restriction.locations
    }
  }

  tags = merge(var.tags, { Name = "${local.name}-${each.key}" })
}

resource "aws_route53_record" "alias" {
  for_each = local.step_two ? local.aliases : {}

  zone_id = var.zone_id
  name    = local.fqdns[each.value]
  type    = split("/", each.key)[1]

  alias {
    name                   = aws_cloudfront_distribution.this[each.value].domain_name
    zone_id                = aws_cloudfront_distribution.this[each.value].hosted_zone_id
    evaluate_target_health = false
  }
}

# ---------------------------------------------------------------------------
# Standard logging v2: CloudWatch Logs in us-east-1 by default, S3 in the log-archive account when log_bucket_arn is set
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "access" {
  count = local.to_s3 ? 0 : 1

  name              = "/aws/vendedlogs/cloudfront/${local.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
  tags              = var.tags
}

data "aws_iam_policy_document" "delivery" {
  count = local.to_s3 ? 0 : 1

  statement {
    sid       = "VendedLogDelivery"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.access[0].arn}:log-stream:*"]

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "delivery" {
  count = local.to_s3 ? 0 : 1

  policy_name     = "${local.name}-delivery"
  policy_document = data.aws_iam_policy_document.delivery[0].json
}

resource "aws_cloudwatch_log_delivery_destination" "access" {
  name          = "${local.name}-access"
  output_format = local.to_s3 ? "parquet" : "json"

  delivery_destination_configuration {
    destination_resource_arn = local.to_s3 ? var.log_bucket_arn : aws_cloudwatch_log_group.access[0].arn
  }

  tags = var.tags

  depends_on = [aws_cloudwatch_log_resource_policy.delivery]
}

resource "aws_cloudwatch_log_delivery_source" "access" {
  for_each = aws_cloudfront_distribution.this

  name         = "${local.name}-${each.key}"
  log_type     = "ACCESS_LOGS"
  resource_arn = each.value.arn
  tags         = var.tags
}

resource "aws_cloudwatch_log_delivery" "access" {
  for_each = aws_cloudwatch_log_delivery_source.access

  delivery_source_name     = each.value.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.access.arn
  record_fields            = var.log_record_fields

  dynamic "s3_delivery_configuration" {
    for_each = local.to_s3 ? [1] : []
    content {
      suffix_path                 = "cloudfront/${var.environment}/{DistributionId}/{yyyy}/{MM}/{dd}/{HH}"
      enable_hive_compatible_path = false
    }
  }

  tags = var.tags
}
