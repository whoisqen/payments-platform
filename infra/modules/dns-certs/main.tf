locals {
  name = "${var.name_prefix}-${var.environment}-glob-dns"

  # Keys come from configuration, so for_each is known at plan time.
  validation_names = merge([
    for ck, c in var.certificates : {
      for n in distinct(concat([c.domain_name], c.subject_alternative_names)) : "${ck}/${n}" => { cert = ck, name = n }
    }
  ]...)

  validation_options = {
    for k, v in local.validation_names : k => one([
      for d in aws_acm_certificate.this[v.cert].domain_validation_options : d if d.domain_name == v.name
    ])
  }
}

resource "aws_route53_zone" "this" {
  name          = var.zone_name
  comment       = "Public zone of ${var.zone_name}"
  force_destroy = false
  tags          = merge(var.tags, { Name = local.name })
}

resource "aws_route53_record" "caa" {
  zone_id = aws_route53_zone.this.zone_id
  name    = var.zone_name
  type    = "CAA"
  ttl     = 3600
  records = [for i in var.caa_issuers : "0 issue \"${i}\""]
}

resource "aws_route53_key_signing_key" "this" {
  count = var.enable_dnssec ? 1 : 0

  hosted_zone_id             = aws_route53_zone.this.zone_id
  key_management_service_arn = var.dnssec_kms_key_arn
  name                       = "${local.name}-ksk"
}

resource "aws_route53_hosted_zone_dnssec" "this" {
  count = length(aws_route53_key_signing_key.this)

  hosted_zone_id = aws_route53_key_signing_key.this[0].hosted_zone_id
}

resource "aws_acm_certificate" "this" {
  for_each = var.certificates

  domain_name               = each.value.domain_name
  subject_alternative_names = each.value.subject_alternative_names
  validation_method         = "DNS"
  key_algorithm             = "EC_prime256v1"
  tags                      = merge(var.tags, { Name = "${local.name}-${each.key}" })

  lifecycle {
    create_before_destroy = true
  }
}

# The apex and its wildcard share one validation record, hence allow_overwrite.
resource "aws_route53_record" "validation" {
  for_each = local.validation_options

  zone_id         = aws_route53_zone.this.zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  for_each = var.certificates

  certificate_arn         = aws_acm_certificate.this[each.key].arn
  validation_record_fqdns = [for k, r in aws_route53_record.validation : r.fqdn if startswith(k, "${each.key}/")]
}
