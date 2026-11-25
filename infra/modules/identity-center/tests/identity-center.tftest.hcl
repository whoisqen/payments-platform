mock_provider "aws" {
  mock_data "aws_identitystore_group" {
    defaults = {
      group_id = "9067b4e1c2-11111111-2222-3333-4444-555555555555"
    }
  }
  mock_data "aws_identitystore_user" {
    defaults = {
      user_id = "9067b4e1c2-66666666-7777-8888-9999-000000000000"
    }
  }
  mock_resource "aws_ssoadmin_permission_set" {
    defaults = {
      arn = "arn:aws:sso:::permissionSet/ssoins-0123456789abcdef/ps-0123456789abcdef"
    }
  }
}

variables {
  instance_arn      = "arn:aws:sso:::instance/ssoins-0123456789abcdef"
  identity_store_id = "d-0123456789"
  accounts = {
    management      = "555555555555"
    shared_services = "222222222222"
    stage           = "333333333333"
    prod            = "444444444444"
  }
  cde_accounts    = ["prod"]
  sre_view_groups = ["pay-sre"]
  assignments = {
    management = { Admin = ["pay-aws-admins"], Billing = ["pay-finance"] }
    stage      = { PlatformAdmin = ["pay-platform"], ReadOnly = ["pay-engineering"] }
  }
  tags = {
    team          = "platform"
    owner         = "platform@example.com"
    "pci-scope"   = "connected"
    "data-class"  = "internal"
    "backup-tier" = "none"
  }
}

run "permission_sets_and_standing_access" {
  command = apply

  assert {
    condition     = toset(keys(aws_ssoadmin_permission_set.this)) == toset(["Admin", "PlatformAdmin", "SRE-View", "ReadOnly", "Billing", "SRE-CDE"])
    error_message = "the six permission sets exist"
  }

  assert {
    condition     = aws_ssoadmin_permission_set.this["SRE-CDE"].session_duration == "PT1H" && aws_ssoadmin_permission_set.this["Admin"].session_duration == "PT1H"
    error_message = "SRE-CDE and Admin sessions last one hour"
  }

  assert {
    condition     = alltrue([for a in ["management", "shared_services", "stage", "prod"] : contains(keys(aws_ssoadmin_account_assignment.standing), "${a}/SRE-View/pay-sre")])
    error_message = "SRE-View reaches every account"
  }

  assert {
    condition     = length(aws_ssoadmin_account_assignment.cde_jit) == 0 && alltrue([for k in keys(aws_ssoadmin_account_assignment.standing) : !strcontains(k, "SRE-CDE")])
    error_message = "SRE-CDE has no standing assignment"
  }

  assert {
    condition     = contains(jsondecode(aws_ssoadmin_permission_set_inline_policy.this["ReadOnly"].inline_policy).Statement[0].Action, "s3:GetObject")
    error_message = "ReadOnly denies data-plane reads"
  }
}

run "admin_outside_management_is_rejected" {
  command = plan

  variables {
    assignments = { stage = { Admin = ["pay-aws-admins"] } }
  }

  expect_failures = [var.assignments]
}

run "standing_sre_cde_is_rejected" {
  command = plan

  variables {
    assignments = { prod = { "SRE-CDE" = ["pay-sre"] } }
  }

  expect_failures = [var.assignments]
}

run "grant_within_one_hour_is_assigned" {
  command = apply

  variables {
    cde_jit_grants = [{ account = "prod", user = "oncall@example.com", expires_at = timeadd(timestamp(), "30m"), reason = "INC-1234" }]
  }

  assert {
    condition     = aws_ssoadmin_account_assignment.cde_jit["prod/user/oncall@example.com"].principal_type == "USER" && aws_ssoadmin_account_assignment.cde_jit["prod/user/oncall@example.com"].target_id == "444444444444"
    error_message = "a valid grant assigns SRE-CDE to the user in the CDE account"
  }
}

run "grant_beyond_one_hour_is_rejected" {
  command = plan

  variables {
    cde_jit_grants = [{ account = "prod", group = "pay-sre", expires_at = "2099-01-01T00:00:00Z", reason = "INC-1234" }]
  }

  expect_failures = [aws_ssoadmin_account_assignment.cde_jit]
}

run "expired_grant_is_rejected" {
  command = plan

  variables {
    cde_jit_grants = [{ account = "prod", group = "pay-sre", expires_at = "2020-01-01T00:00:00Z", reason = "INC-1234" }]
  }

  expect_failures = [aws_ssoadmin_account_assignment.cde_jit]
}

run "revocation_run_drops_expired_grant" {
  command = apply

  variables {
    revocation_run = true
    cde_jit_grants = [{ account = "prod", group = "pay-sre", expires_at = "2020-01-01T00:00:00Z", reason = "INC-1234" }]
  }

  assert {
    condition     = length(aws_ssoadmin_account_assignment.cde_jit) == 0
    error_message = "an expired grant has no assignment in a revocation run"
  }
}

run "grant_outside_cde_account_is_rejected" {
  command = plan

  variables {
    cde_jit_grants = [{ account = "stage", group = "pay-sre", expires_at = "2099-01-01T00:00:00Z", reason = "INC-1234" }]
  }

  expect_failures = [var.cde_jit_grants]
}

run "grant_with_group_and_user_is_rejected" {
  command = plan

  variables {
    cde_jit_grants = [{ account = "prod", group = "pay-sre", user = "oncall@example.com", expires_at = "2099-01-01T00:00:00Z", reason = "INC-1234" }]
  }

  expect_failures = [var.cde_jit_grants]
}
