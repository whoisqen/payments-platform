mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/mock" }
  }

  mock_resource "aws_backup_vault" {
    defaults = { arn = "arn:aws:backup:eu-central-1:222222222222:backup-vault:mock" }
  }
}

variables {
  name_prefix        = "pay"
  env                = "prod"
  region_short       = "euc1"
  region_name        = "eu-central-1"
  kms_key_arn        = "arn:aws:kms:eu-central-1:222222222222:key/mrk-0005"
  source_account_ids = ["111111111111"]
  sns_topic_arns     = { "eu-central-1" = "arn:aws:sns:eu-central-1:222222222222:backup" }

  recovery_regions = {
    "us-east-1" = { short = "use1", kms_key_arn = "arn:aws:kms:us-east-1:222222222222:key/mrk-0005" }
    "us-east-2" = { short = "use2", kms_key_arn = "arn:aws:kms:us-east-2:222222222222:key/mrk-0005" }
  }

  tags = {
    team          = "platform"
    owner         = "platform@example.com"
    "pci-scope"   = "cde"
    "data-class"  = "card-data"
    "backup-tier" = "gold"
  }
}

run "vaults_are_locked_in_compliance_mode" {
  command = apply

  assert {
    condition     = length(aws_backup_vault.this) == 3 && length(aws_backup_vault_lock_configuration.this) == 3
    error_message = "a locked vault in each of the three regions"
  }

  assert {
    condition     = alltrue([for l in aws_backup_vault_lock_configuration.this : l.changeable_for_days == 3 && l.min_retention_days == 7 && l.max_retention_days == 2555])
    error_message = "compliance lock with 7 to 2555 days covers every rule"
  }

  assert {
    condition     = strcontains(aws_backup_vault_policy.this["us-east-1"].policy, "backup:CopyIntoBackupVault") && strcontains(aws_backup_vault_policy.this["us-east-1"].policy, "arn:aws:iam::111111111111:root")
    error_message = "vault policy admits copies from the source account only"
  }

  assert {
    condition     = length(aws_backup_vault_notifications.this) == 1
    error_message = "notifications only where a topic exists"
  }
}

run "tiers_select_by_tag_and_copy_to_both_regions" {
  command = apply

  variables {
    recovery_regions = {}
    copy_vault_arns = {
      "us-east-1" = "arn:aws:backup:us-east-1:222222222222:backup-vault:pay-prod-use1-backup"
      "us-east-2" = "arn:aws:backup:us-east-2:222222222222:backup-vault:pay-prod-use2-backup"
    }
  }

  assert {
    condition     = length(aws_backup_plan.tier) == 3 && alltrue([for t, s in aws_backup_selection.tier : one(s.selection_tag).key == "backup-tier" && one(s.selection_tag).value == t])
    error_message = "one plan and one tag selection per tier"
  }

  assert {
    condition = (
      length(aws_backup_plan.tier["gold"].rule) == 3 &&
      anytrue([for r in aws_backup_plan.tier["gold"].rule : r.rule_name == "hourly" && r.schedule == "cron(0 * * * ? *)" && length(r.copy_action) == 2 && one(r.lifecycle).delete_after == 35]) &&
      anytrue([for r in aws_backup_plan.tier["gold"].rule : r.rule_name == "continuous" && r.enable_continuous_backup && one(r.lifecycle).delete_after == 35]) &&
      anytrue([for r in aws_backup_plan.tier["gold"].rule : r.rule_name == "monthly" && one(r.lifecycle).delete_after == 2555 && length(r.copy_action) == 2])
    )
    error_message = "gold: hourly 35 d with two copies, continuous 35 d, monthly 7 years"
  }

  assert {
    condition     = alltrue([for r in aws_backup_plan.tier["gold"].rule : r.rule_name == "monthly" || one(r.lifecycle).cold_storage_after == null])
    error_message = "no cold storage for managed snapshots"
  }

  assert {
    condition     = length(aws_backup_plan.tier["bronze"].rule) == 1 && one(aws_backup_plan.tier["bronze"].rule).enable_continuous_backup == false && length(one(aws_backup_plan.tier["bronze"].rule).copy_action) == 0
    error_message = "bronze is a single daily rule without copies"
  }
}

run "daily_restore_test_of_application_databases" {
  command = apply

  assert {
    condition     = aws_backup_restore_testing_plan.application_databases[0].schedule_expression == "cron(0 4 * * ? *)" && length(aws_backup_restore_testing_selection.application_databases) == 2
    error_message = "daily restore test for Aurora and DynamoDB"
  }
}

run "backup_account_stack_holds_only_vaults" {
  command = apply

  variables {
    create_plans = false
  }

  assert {
    condition     = length(aws_backup_vault.this) == 3 && length(aws_backup_plan.tier) == 0 && length(aws_backup_restore_testing_plan.application_databases) == 0
    error_message = "no plans in a vault-only stack"
  }
}

run "recovery_role_makes_one_vault" {
  command = apply

  variables {
    region_role      = "recovery"
    region_name      = "us-east-1"
    region_short     = "use1"
    recovery_regions = {}
    sns_topic_arns   = {}
  }

  assert {
    condition     = length(aws_backup_vault.this) == 1 && length(aws_backup_plan.tier) == 0
    error_message = "a recovery stack holds one vault and no plans"
  }
}

run "prod_cannot_skip_the_lock" {
  command = plan

  variables {
    vault_lock_enabled = false
  }

  expect_failures = [var.vault_lock_enabled]
}

run "lock_minimum_above_bronze_is_rejected" {
  command = plan

  variables {
    min_retention_days = 14
  }

  expect_failures = [var.min_retention_days]
}

run "tag_schema_is_enforced" {
  command = plan

  variables {
    tags = { team = "platform" }
  }

  expect_failures = [var.tags]
}
