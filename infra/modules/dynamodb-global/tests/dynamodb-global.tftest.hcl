mock_provider "aws" {}

variables {
  env          = "prod"
  region_short = "euc1"
  account_id   = "111111111111"
  kms_key_arn  = "arn:aws:kms:eu-central-1:111111111111:key/mrk-0002"

  recovery_regions = {
    "us-east-1" = { kms_key_arn = "arn:aws:kms:us-east-1:111111111111:key/mrk-0002" }
    "us-east-2" = { kms_key_arn = "arn:aws:kms:us-east-2:111111111111:key/mrk-0002" }
  }

  tags = {
    team          = "payments-core"
    owner         = "payments-core@example.com"
    "pci-scope"   = "cde"
    "data-class"  = "internal"
    "backup-tier" = "gold"
  }
}

run "global_table_with_pitr_and_replicas" {
  command = apply

  assert {
    condition     = aws_dynamodb_table.this.name == "pay-prod-euc1-merchant-cell-map" && aws_dynamodb_table.this.point_in_time_recovery[0].enabled && aws_dynamodb_table.this.point_in_time_recovery[0].recovery_period_in_days == 35
    error_message = "name and 35-day PITR"
  }

  assert {
    condition     = length(aws_dynamodb_table.this.replica) == 2 && alltrue([for r in aws_dynamodb_table.this.replica : r.consistency_mode == "EVENTUAL" && r.point_in_time_recovery])
    error_message = "two MREC replicas with PITR"
  }

  assert {
    condition     = aws_dynamodb_table.this.stream_enabled
    error_message = "replicas need streams"
  }
}

run "writes_denied_in_both_recovery_regions" {
  command = plan

  assert {
    condition = (
      strcontains(aws_iam_policy.deny_recovery_writes.policy, "\"Effect\":\"Deny\"") &&
      strcontains(aws_iam_policy.deny_recovery_writes.policy, "arn:aws:dynamodb:us-east-1:111111111111:table/pay-prod-euc1-merchant-cell-map") &&
      strcontains(aws_iam_policy.deny_recovery_writes.policy, "arn:aws:dynamodb:us-east-2:111111111111:table/pay-prod-euc1-merchant-cell-map") &&
      !strcontains(aws_iam_policy.deny_recovery_writes.policy, "eu-central-1")
    )
    error_message = "deny must cover both recovery regions and never Frankfurt"
  }
}

run "switch_moves_the_deny" {
  command = plan

  variables {
    deny_write_regions = ["eu-central-1", "us-east-2"]
  }

  assert {
    condition     = !strcontains(aws_iam_policy.deny_recovery_writes.policy, "us-east-1")
    error_message = "the switched region must be allowed to write"
  }
}

run "tag_schema_is_enforced" {
  command = plan

  variables {
    tags = { team = "payments-core" }
  }

  expect_failures = [var.tags]
}
