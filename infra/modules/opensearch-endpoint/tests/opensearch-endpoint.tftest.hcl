mock_provider "aws" {}

variables {
  name_prefix        = "pay"
  env                = "dev"
  region_short       = "euc1"
  domain_arn         = "arn:aws:es:eu-central-1:222222222222:domain/pay-shared-euc1-logs"
  vpc_id             = "vpc-1"
  subnet_ids         = ["subnet-1", "subnet-2", "subnet-3"]
  client_cidr_blocks = ["10.120.0.0/16"]
  tags = {
    team          = "platform"
    owner         = "platform@example.com"
    "pci-scope"   = "out-of-scope"
    "data-class"  = "internal"
    "backup-tier" = "none"
  }
}

run "endpoint_admits_only_the_environment_vpc" {
  command = plan

  assert {
    condition     = aws_opensearch_vpc_endpoint.this.domain_arn == var.domain_arn && aws_security_group.this.name == "pay-dev-euc1-logs-endpoint"
    error_message = "endpoint of the central domain with its own group"
  }

  assert {
    condition     = [for r in aws_vpc_security_group_ingress_rule.clients : r.cidr_ipv4] == ["10.120.0.0/16"] && alltrue([for r in aws_vpc_security_group_ingress_rule.clients : r.from_port == 443 && r.to_port == 443])
    error_message = "443 from the environment VPC only"
  }
}

run "cde_name_is_rejected" {
  command = plan

  variables {
    env = "cde-prod"
  }

  expect_failures = [var.env]
}
