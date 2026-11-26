mock_provider "aws" {}

variables {
  name_prefix         = "pay"
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
    condition     = aws_networkfirewall_rule_group.psp_allowlist[0].rule_group[0].rules_source[0].rules_source_list[0].generated_rules_type == "ALLOWLIST"
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

run "fence_group_comes_before_the_allowlist" {
  command = plan

  assert {
    condition     = aws_networkfirewall_rule_group.psp_fence.name == "pay-prod-euc1-psp-fence"
    error_message = "the failover script finds the group by this name"
  }

  assert {
    condition     = length([for r in aws_networkfirewall_firewall_policy.this.firewall_policy[0].stateful_rule_group_reference : r if r.priority <= 2]) == 2
    error_message = "the fence is evaluated first"
  }
}

run "no_ci_allowlist_by_default" {
  command = plan

  assert {
    condition     = length(aws_networkfirewall_rule_group.ci_allowlist) == 0 && sort([for r in aws_networkfirewall_firewall_policy.this.firewall_policy[0].stateful_rule_group_reference : tostring(r.priority)]) == tolist(["1", "2"])
    error_message = "the CI allowlist exists only for given runner CIDRs"
  }
}

run "ci_allowlist_applies_only_to_the_untrusted_tier" {
  command = plan

  variables {
    ci_source_cidrs = ["10.140.104.0/22", "10.140.108.0/22", "10.140.112.0/22"]
  }

  assert {
    condition     = one(one(aws_networkfirewall_rule_group.ci_allowlist[0].rule_group[0].rule_variables[0].ip_sets).ip_set).definition == toset(["10.140.104.0/22", "10.140.108.0/22", "10.140.112.0/22"]) && one(aws_networkfirewall_rule_group.ci_allowlist[0].rule_group[0].rule_variables[0].ip_sets).key == "HOME_NET"
    error_message = "HOME_NET of the CI allowlist is the untrusted tier"
  }
  assert {
    condition     = aws_networkfirewall_rule_group.ci_allowlist[0].rule_group[0].rules_source[0].rules_source_list[0].generated_rules_type == "ALLOWLIST" && contains(aws_networkfirewall_rule_group.ci_allowlist[0].rule_group[0].rules_source[0].rules_source_list[0].targets, "api.github.com") && contains(aws_networkfirewall_rule_group.ci_allowlist[0].rule_group[0].rules_source[0].rules_source_list[0].targets, ".blob.core.windows.net")
    error_message = "the CI allowlist passes only the listed domains"
  }
  assert {
    condition     = sort([for r in aws_networkfirewall_firewall_policy.this.firewall_policy[0].stateful_rule_group_reference : tostring(r.priority)]) == tolist(["1", "2", "4"]) && contains(aws_networkfirewall_firewall_policy.this.firewall_policy[0].stateful_default_actions, "aws:drop_established")
    error_message = "the CI allowlist is in the policy and everything else is still dropped"
  }
}

run "ci_allowlist_rejects_any_source" {
  command = plan

  variables {
    ci_source_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.ci_source_cidrs]
}

run "ci_only_egress_has_no_psp_allowlist" {
  command = plan

  variables {
    psp_domains     = []
    ci_source_cidrs = ["10.140.104.0/22"]
  }

  assert {
    condition     = length(aws_networkfirewall_rule_group.psp_allowlist) == 0 && length(aws_networkfirewall_rule_group.ci_allowlist) == 1
    error_message = "a CI egress VPC passes CI domains only"
  }
  assert {
    condition     = sort([for r in aws_networkfirewall_firewall_policy.this.firewall_policy[0].stateful_rule_group_reference : tostring(r.priority)]) == tolist(["1", "4"])
    error_message = "the fence stays first, then the CI allowlist"
  }
}

run "empty_allowlists_are_rejected" {
  command = plan

  variables {
    psp_domains = []
  }

  expect_failures = [var.psp_domains]
}

run "trusted_runners_get_extra_aws_domains_before_the_ci_allowlist" {
  command = plan

  variables {
    psp_domains             = []
    ci_source_cidrs         = ["10.140.0.0/16"]
    ci_trusted_source_cidrs = ["10.140.0.0/19", "10.140.32.0/19", "10.140.64.0/19"]
  }

  assert {
    condition     = one(one(aws_networkfirewall_rule_group.ci_trusted[0].rule_group[0].rule_variables[0].ip_sets).ip_set).definition == toset(["10.140.0.0/19", "10.140.32.0/19", "10.140.64.0/19"])
    error_message = "only the trusted tier gets the extra domains"
  }
  assert {
    condition     = can(regex("tls.sni; content:\"sts.amazonaws.com\"", aws_networkfirewall_rule_group.ci_trusted[0].rule_group[0].rules_source[0].rules_string)) && !can(regex("(?m)^(drop|reject|alert)", aws_networkfirewall_rule_group.ci_trusted[0].rule_group[0].rules_source[0].rules_string))
    error_message = "the trusted group only passes listed domains and drops nothing itself"
  }
  assert {
    condition     = sort([for r in aws_networkfirewall_firewall_policy.this.firewall_policy[0].stateful_rule_group_reference : tostring(r.priority)]) == tolist(["1", "3", "4"])
    error_message = "fence, then the trusted extras, then the CI allowlist"
  }
}
