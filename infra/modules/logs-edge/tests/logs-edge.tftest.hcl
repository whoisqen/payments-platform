mock_provider "aws" {
  mock_data "aws_lb" {
    defaults = { dns_name = "logs-nlb.elb.eu-central-1.amazonaws.com", zone_id = "Z0000000000000" }
  }
}
mock_provider "tls" {}
mock_provider "time" {}

variables {
  name_prefix               = "pay"
  host                      = "logs.observability.pay.example.com"
  certificate_authority_arn = "arn:aws:acm-pca:eu-central-1:222222222222:certificate-authority/ca-1"
  kms_key_arn               = "arn:aws:kms:eu-central-1:222222222222:key/mrk-shared"
  vpc_ids                   = ["vpc-1"]
  tags = {
    team          = "platform"
    owner         = "platform@example.com"
    "pci-scope"   = "out-of-scope"
    "data-class"  = "internal"
    "backup-tier" = "none"
  }
}

run "server_identity_comes_from_the_private_ca" {
  command = plan

  assert {
    condition = (
      aws_secretsmanager_secret.tls.name == "pay/shared-services/logstash/tls" &&
      aws_acmpca_certificate.server.signing_algorithm == "SHA256WITHECDSA" &&
      aws_acmpca_certificate.server.certificate_authority_arn == var.certificate_authority_arn &&
      tls_cert_request.server.dns_names == tolist(["logs.observability.pay.example.com"])
    )
    error_message = "the certificate of the logs host is issued by the private CA into the Logstash secret"
  }

  assert {
    condition     = length(aws_route53_record.host) == 0 && aws_route53_zone.host.name == "logs.observability.pay.example.com"
    error_message = "the first step creates the zone of the host only"
  }
}

run "second_step_aliases_the_nlb" {
  command = plan

  variables {
    nlb_lookup_enabled = true
  }

  assert {
    condition     = aws_route53_record.host[0].alias[0].name == "logs-nlb.elb.eu-central-1.amazonaws.com"
    error_message = "the host points at the NLB of the logs Gateway"
  }
}

run "rotation_must_precede_expiry" {
  command = plan

  variables {
    rotation_days = 400
  }

  expect_failures = [time_rotating.certificate]
}
