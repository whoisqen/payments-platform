mock_provider "aws" {
  mock_data "aws_guardduty_detector" {
    defaults = { id = "12abc34d567e8fa901bc2d34e56789f0" }
  }
  mock_resource "aws_securityhub_configuration_policy" {
    defaults = { id = "a1b2c3d4-5678-90ab-cdef-111111111111" }
  }
}

variables {
  region_short       = "euc1"
  region_name        = "eu-central-1"
  regions            = ["eu-central-1", "us-east-1"]
  admin_account_id   = "777777777777"
  root_id            = "r-ab12"
  member_account_ids = ["111111111111", "333333333333"]
  cde_account_ids    = ["555555555555"]

  tags = {
    team          = "security"
    owner         = "security@example.com"
    "pci-scope"   = "connected"
    "data-class"  = "internal"
    "backup-tier" = "none"
  }
}

run "management_designates_the_audit_account" {
  command = apply

  variables {
    mode = "management"
  }

  assert {
    condition = (
      length(aws_guardduty_organization_admin_account.this) == 2 &&
      length(aws_inspector2_delegated_admin_account.this) == 2 &&
      length(aws_macie2_organization_admin_account.this) == 2 &&
      aws_securityhub_organization_admin_account.this[0].region == "eu-central-1"
    )
    error_message = "GuardDuty, Inspector and Macie in every region, Security Hub in the home region"
  }

  assert {
    condition     = alltrue([for a in aws_guardduty_organization_admin_account.this : a.admin_account_id == "777777777777"])
    error_message = "the audit account is the delegated administrator"
  }

  assert {
    condition     = length(aws_guardduty_organization_configuration.this) == 0 && length(aws_securityhub_configuration_policy.this) == 0
    error_message = "management mode configures nothing on the admin side"
  }
}

run "admin_enables_guardduty_for_all_members" {
  command = apply

  variables {
    mode = "admin"
  }

  assert {
    condition     = alltrue([for c in aws_guardduty_organization_configuration.this : c.auto_enable_organization_members == "ALL"]) && length(aws_guardduty_organization_configuration.this) == 2
    error_message = "every member in every region"
  }

  assert {
    condition = alltrue([for f in ["S3_DATA_EVENTS", "EKS_AUDIT_LOGS", "EBS_MALWARE_PROTECTION", "RDS_LOGIN_EVENTS", "RUNTIME_MONITORING"] :
    contains([for k, v in aws_guardduty_organization_configuration_feature.this : v.name if v.region == "eu-central-1"], f)])
    error_message = "S3, EKS, malware, RDS and runtime protection are on"
  }

  assert {
    condition     = one(aws_guardduty_organization_configuration_feature.this["eu-central-1/RUNTIME_MONITORING"].additional_configuration).name == "EKS_ADDON_MANAGEMENT"
    error_message = "runtime monitoring manages the EKS add-on"
  }
}

run "admin_centralizes_security_hub" {
  command = apply

  variables {
    mode = "admin"
  }

  assert {
    condition     = aws_securityhub_organization_configuration.this[0].organization_configuration[0].configuration_type == "CENTRAL"
    error_message = "central configuration"
  }

  assert {
    condition     = toset(aws_securityhub_finding_aggregator.this[0].specified_regions) == toset(["us-east-1"])
    error_message = "the home region aggregates the other regions"
  }

  assert {
    condition = (
      contains(aws_securityhub_configuration_policy.this[0].configuration_policy[0].enabled_standard_arns, "arn:aws:securityhub:eu-central-1::standards/pci-dss/v/4.0.1") &&
      contains(aws_securityhub_configuration_policy.this[0].configuration_policy[0].enabled_standard_arns, "arn:aws:securityhub:eu-central-1::standards/aws-foundational-security-best-practices/v/1.0.0")
    )
    error_message = "PCI DSS and AWS foundational standards"
  }

  assert {
    condition     = aws_securityhub_configuration_policy_association.root[0].target_id == "r-ab12"
    error_message = "the policy applies to the whole organization"
  }
}

run "admin_enables_inspector_and_macie" {
  command = apply

  variables {
    mode = "admin"
  }

  assert {
    condition = alltrue([for c in aws_inspector2_organization_configuration.this :
    c.auto_enable[0].ec2 && c.auto_enable[0].ecr && c.auto_enable[0].lambda])
    error_message = "Inspector auto-enables EC2, ECR and Lambda"
  }

  assert {
    condition     = length(aws_inspector2_member_association.this) == 4 && toset(aws_inspector2_enabler.this["us-east-1"].account_ids) == toset(["777777777777", "111111111111", "333333333333"])
    error_message = "existing members are associated and enabled in every region"
  }

  assert {
    condition     = alltrue([for c in aws_macie2_organization_configuration.this : c.auto_enable])
    error_message = "Macie auto-enables new members"
  }

  assert {
    condition     = tolist(one(one(one(one(aws_macie2_classification_job.cde[0].s3_job_definition).bucket_criteria).includes).and).simple_criterion[0].values) == tolist(["555555555555"])
    error_message = "the Macie job scans the CDE accounts"
  }

  assert {
    condition     = length(aws_shield_subscription.this) == 0
    error_message = "Shield Advanced is off by default"
  }
}

run "shield_is_optional" {
  command = plan

  variables {
    mode                    = "admin"
    shield_advanced_enabled = true
  }

  assert {
    condition     = aws_shield_subscription.this[0].auto_renew == "ENABLED"
    error_message = "the subscription renews"
  }
}

run "security_hub_needs_the_root" {
  command = plan

  variables {
    mode    = "admin"
    root_id = ""
  }

  expect_failures = [aws_securityhub_configuration_policy.this]
}
