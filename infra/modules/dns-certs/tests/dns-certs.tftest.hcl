mock_provider "aws" {}

variables {
  environment = "prod"
  zone_name   = "pay.example.com"
  certificates = {
    api = { domain_name = "api.pay.example.com", subject_alternative_names = ["*.api.pay.example.com"] }
  }
  tags = {
    environment = "prod", team = "platform", owner = "platform@example.com", cost-center = "cc-100", cell = "shared"
    component   = "dns", pci-scope = "connected", data-class = "public", backup-tier = "none", managed-by = "terraform", repo = "infra/modules/dns-certs"
  }
}

run "zone_caa_and_certificate" {
  command = plan

  override_resource {
    target          = aws_acm_certificate.this["api"]
    override_during = plan
    values = {
      arn = "arn:aws:acm:eu-central-1:111111111111:certificate/00000000-0000-0000-0000-000000000000"
      domain_validation_options = [
        { domain_name = "api.pay.example.com", resource_record_name = "_a.api.pay.example.com.", resource_record_type = "CNAME", resource_record_value = "_b.acm-validations.aws." },
        { domain_name = "*.api.pay.example.com", resource_record_name = "_a.api.pay.example.com.", resource_record_type = "CNAME", resource_record_value = "_b.acm-validations.aws." },
      ]
    }
  }

  assert {
    condition     = aws_route53_zone.this.name == "pay.example.com" && !aws_route53_zone.this.force_destroy
    error_message = "zone is kept on destroy"
  }
  assert {
    condition     = contains(aws_route53_record.caa.records, "0 issue \"amazon.com\"") && length(aws_route53_record.caa.records) == 5
    error_message = "only ACM and Let's Encrypt may issue"
  }
  assert {
    condition     = aws_acm_certificate.this["api"].validation_method == "DNS" && length(aws_route53_record.validation) == 2
    error_message = "DNS validation with a record per name"
  }
  assert {
    condition     = length(aws_route53_key_signing_key.this) == 0
    error_message = "DNSSEC is off without a key"
  }
}

run "dnssec_with_key" {
  command = plan

  variables {
    certificates       = {}
    enable_dnssec      = true
    dnssec_kms_key_arn = "arn:aws:kms:us-east-1:111111111111:key/01234567-89ab-cdef-0123-456789abcdef"
  }

  assert {
    condition     = length(aws_route53_key_signing_key.this) == 1 && length(aws_route53_hosted_zone_dnssec.this) == 1
    error_message = "DNSSEC is on"
  }
}

run "bad_zone_rejected" {
  command = plan

  variables {
    certificates = {}
    zone_name    = "NotADomain"
  }

  expect_failures = [var.zone_name]
}
