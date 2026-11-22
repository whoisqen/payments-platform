mock_provider "aws" {}

variables {
  account_id      = "111111111111"
  region          = "eu-central-1"
  environment     = "prod"
  component       = "state"
  admin_role_arns = ["arn:aws:iam::111111111111:role/pay-prod-glob-key-admin"]
  user_role_arns  = ["arn:aws:iam::111111111111:role/pay-prod-glob-tf-apply-network"]
  tags = {
    environment = "prod", team = "platform", owner = "platform@example.com", cost-center = "cc-100", cell = "shared"
    component   = "kms", pci-scope = "connected", data-class = "internal", backup-tier = "gold", managed-by = "terraform", repo = "infra/modules/kms"
  }
}

run "primary_is_multi_region_and_rotated" {
  command = plan

  assert {
    condition     = aws_kms_key.primary[0].multi_region && aws_kms_key.primary[0].enable_key_rotation
    error_message = "primary must be multi-Region with rotation"
  }
  assert {
    condition     = aws_kms_alias.this.name == "alias/pay-prod-euc1-state"
    error_message = "alias follows pay-<env>-<region-short>-<component>"
  }
  assert {
    condition     = length(aws_kms_replica_key.replica) == 0
    error_message = "no replica without primary_key_arn"
  }
  assert {
    condition     = length(jsondecode(aws_kms_key.primary[0].policy).Statement) == 3
    error_message = "policy holds root, administrators and users"
  }
}

run "administrators_cannot_use_the_key" {
  command = plan

  assert {
    condition     = !contains(flatten([for s in jsondecode(aws_kms_key.primary[0].policy).Statement : s.Action if s.Sid == "KeyAdministration"]), "kms:Decrypt")
    error_message = "administrators have no crypto actions"
  }
}

run "replica_in_recovery_region" {
  command = plan

  variables {
    region          = "us-east-1"
    is_replica      = true
    primary_key_arn = "arn:aws:kms:eu-central-1:111111111111:key/mrk-0123456789abcdef0123456789abcdef"
  }

  assert {
    condition     = length(aws_kms_key.primary) == 0 && aws_kms_replica_key.replica[0].primary_key_arn == var.primary_key_arn
    error_message = "replica only"
  }
  assert {
    condition     = aws_kms_alias.this.name == "alias/pay-prod-use1-state"
    error_message = "replica alias uses the recovery region short name"
  }
}

run "replica_needs_primary_arn" {
  command = plan

  variables {
    is_replica = true
  }

  expect_failures = [var.primary_key_arn]
}

run "required_tags_enforced" {
  command = plan

  variables {
    tags = { team = "platform" }
  }

  expect_failures = [var.tags]
}
