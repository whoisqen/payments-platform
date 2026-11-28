locals {
  secret_name  = "${var.name_prefix}/shared-services/logstash/tls"
  ec           = startswith(var.ca_key_algorithm, "EC")
  signing_algo = local.ec ? "SHA256WITHECDSA" : "SHA256WITHRSA"
}

# A new key and certificate on the first apply after rotation_days; Terraform alone handles the key (the state is KMS-encrypted).
resource "time_rotating" "certificate" {
  rotation_days = var.rotation_days

  lifecycle {
    precondition {
      condition     = var.rotation_days < var.validity_days
      error_message = "rotation_days must be shorter than validity_days."
    }
  }
}

resource "tls_private_key" "server" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"

  lifecycle {
    replace_triggered_by = [time_rotating.certificate]
  }
}

resource "tls_cert_request" "server" {
  private_key_pem = tls_private_key.server.private_key_pem
  dns_names       = [var.host]

  subject {
    common_name = var.host
  }
}

resource "aws_acmpca_certificate" "server" {
  certificate_authority_arn   = var.certificate_authority_arn
  certificate_signing_request = tls_cert_request.server.cert_request_pem
  signing_algorithm           = local.signing_algo
  template_arn                = "arn:aws:acm-pca:::template/EndEntityServerAuthCertificate/V1"

  validity {
    type  = "DAYS"
    value = var.validity_days
  }
}

data "aws_acmpca_certificate_authority" "this" {
  arn = var.certificate_authority_arn
}

resource "aws_secretsmanager_secret" "tls" {
  # checkov:skip=CKV2_AWS_57: rotation is time_rotating in this module; each apply after rotation_days writes a new version
  name        = local.secret_name
  description = "Logstash TLS server: tls.crt (certificate and chain), tls.key (PKCS#8), ca.crt (CA of the collector client certificates)"
  kms_key_id  = var.kms_key_arn

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "tls" {
  secret_id = aws_secretsmanager_secret.tls.id
  secret_string = jsonencode({
    "tls.crt" = "${aws_acmpca_certificate.server.certificate}\n${aws_acmpca_certificate.server.certificate_chain}"
    "tls.key" = tls_private_key.server.private_key_pem_pkcs8
    "ca.crt"  = data.aws_acmpca_certificate_authority.this.certificate
  })
}

# A zone of the host alone, so the sibling names of the parent domain still resolve publicly.
resource "aws_route53_zone" "host" {
  # checkov:skip=CKV2_AWS_38: private zone, DNSSEC signing applies to public zones only
  # checkov:skip=CKV2_AWS_39: query logging of private zones goes through the Resolver, not configured per zone
  name    = var.host
  comment = "Logs entry of the central stack (private)"

  dynamic "vpc" {
    for_each = toset(var.vpc_ids)

    content {
      vpc_id = vpc.value
    }
  }

  tags = var.tags
}

# The NLB belongs to the load balancer controller and exists only after the Gateway is synced.
data "aws_lb" "logs" {
  count = var.nlb_lookup_enabled ? 1 : 0

  tags = {
    "service.k8s.aws/stack" = var.nlb_stack_tag
  }
}

resource "aws_route53_record" "host" {
  count = var.nlb_lookup_enabled ? 1 : 0

  zone_id = aws_route53_zone.host.zone_id
  name    = var.host
  type    = "A"

  alias {
    name                   = data.aws_lb.logs[0].dns_name
    zone_id                = data.aws_lb.logs[0].zone_id
    evaluate_target_health = true
  }
}
