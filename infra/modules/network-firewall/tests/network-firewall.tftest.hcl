mock_provider "aws" {}

variables {
  region              = "eu-central-1"
  environment         = "prod"
  vpc_id              = "vpc-0123456789abcdef0"
  firewall_subnet_ids = ["subnet-a1", "subnet-a2", "subnet-a3"]
  nat_subnet_ids      = ["subnet-b1", "subnet-b2", "subnet-b3"]
  psp_domains         = [".adyen.com", "api.stripe.com"]
  enable_logging      = true
  log_bucket_name     = "pay-prod-euc1-firewall-logs"
  tags = {
    environment = "prod", team = "platform", owner = "platform@example.com", cost-center = "cc-100", cell = "shared"
    component   = "egress", pci-scope = "connected", data-class = "internal", backup-tier = "none", managed-by = "terraform", repo = "infra/modules/network-firewall"
  }
}

run "allowlist_and_default_drop" {
  command = plan

  assert {
    condition     = aws_networkfirewall_rule_group.psp_allowlist.rule_group[0].rules_source[0].rules_source_list[0].generated_rules_type == "ALLOWLIST"
    error_message = "only listed domains pass"
  }
  assert {
    condition     = contains(aws_networkfirewall_firewall_policy.this.firewall_policy[0].stateful_default_actions, "aws:drop_established")
    error_message = "unlisted established traffic is dropped"
  }
  assert {
    condition     = aws_networkfirewall_firewall.this.delete_protection
    error_message = "firewall is protected from deletion"
  }
}

run "static_egress_ips_per_az" {
  command = plan

  assert {
    condition     = length(aws_eip.nat) == 3 && length(aws_nat_gateway.this) == 3
    error_message = "one EIP and one NAT gateway per AZ"
  }
  assert {
    condition     = aws_networkfirewall_firewall.this.name == "pay-prod-euc1-egress"
    error_message = "name follows pay-<env>-<region-short>-<component>"
  }
}

run "logging_is_optional" {
  command = plan

  variables {
    enable_logging  = false
    log_bucket_name = null
  }

  assert {
    condition     = length(aws_networkfirewall_logging_configuration.this) == 0
    error_message = "no logging without a bucket"
  }
}

run "bad_domain_rejected" {
  command = plan

  variables {
    psp_domains = ["*.evil"]
  }

  expect_failures = [var.psp_domains]
}
