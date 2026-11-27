mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }

  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/pay-stage-use1-dr-failover-function" }
  }

  mock_resource "aws_sns_topic" {
    defaults = { arn = "arn:aws:sns:us-east-1:111111111111:pay-stage-use1-dr-failover-trigger" }
  }

  mock_resource "aws_lambda_function" {
    defaults = { arn = "arn:aws:lambda:us-east-1:111111111111:function:pay-stage-use1-dr-failover" }
  }

  mock_resource "aws_cloudwatch_metric_alarm" {
    defaults = { arn = "arn:aws:cloudwatch:us-east-1:111111111111:alarm:pay-stage-use1-dr-failover-working-region-down" }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn    = "arn:aws:kms:us-east-1:111111111111:key/22222222-3333-4444-5555-666666666666"
      key_id = "22222222-3333-4444-5555-666666666666"
    }
  }

  mock_resource "aws_dynamodb_table" {
    defaults = { arn = "arn:aws:dynamodb:us-east-1:111111111111:table/pay-stage-use1-dr-lock" }
  }
}
mock_provider "archive" {}


variables {
  name_prefix         = "pay"
  env                 = "stage"
  region_short        = "use1"
  account_id          = "111111111111"
  source_region       = "eu-central-1"
  source_region_short = "euc1"
  cells               = ["cell-0", "cell-1", "locker"]
  health_check_id     = "11111111-2222-3333-4444-555555555555"
  deny_policy_arn     = "arn:aws:iam::111111111111:policy/pay-stage-euc1-merchant-cell-map-deny-recovery-writes"
  fence_rule_group    = "pay-stage-euc1-psp-fence"
  kms_key_arn         = "arn:aws:kms:us-east-1:111111111111:key/mrk-0001"

  tags = {
    team          = "platform"
    owner         = "platform@example.com"
    "pci-scope"   = "cde"
    "data-class"  = "internal"
    "backup-tier" = "gold"
  }
}

run "health_check_alarm_triggers_the_function" {
  command = apply

  assert {
    condition     = aws_cloudwatch_metric_alarm.working_region_down.namespace == "AWS/Route53" && aws_cloudwatch_metric_alarm.working_region_down.dimensions["HealthCheckId"] == var.health_check_id
    error_message = "the alarm watches the Route 53 health check of the working region"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.working_region_down.datapoints_to_alarm == aws_cloudwatch_metric_alarm.working_region_down.evaluation_periods && aws_cloudwatch_metric_alarm.working_region_down.treat_missing_data == "notBreaching"
    error_message = "every period must fail, and missing data must not start a failover"
  }

  assert {
    condition     = aws_lambda_function.failover.reserved_concurrent_executions == 1 && aws_lambda_function.failover.handler == "lambda_handler.handler"
    error_message = "one failover run at a time"
  }

  assert {
    condition     = jsondecode(aws_lambda_function.failover.environment[0].variables.CELLS) == ["cell-0", "cell-1", "locker"] && aws_lambda_function.failover.environment[0].variables.ENVIRONMENT == "stage"
    error_message = "cells and the global cluster naming reach the function"
  }
}

run "lock_table_is_encrypted_and_protected" {
  command = apply

  assert {
    condition     = aws_dynamodb_table.lock.name == "pay-stage-use1-dr-lock" && aws_dynamodb_table.lock.deletion_protection_enabled && aws_dynamodb_table.lock.hash_key == "pk"
    error_message = "lock table name, key and deletion protection"
  }
}

run "trigger_topic_uses_a_key_cloudwatch_can_use" {
  command = apply

  assert {
    condition     = aws_sns_topic.failover.kms_master_key_id != "alias/aws/sns" && aws_sns_topic.failover.kms_master_key_id == aws_kms_key.sns[0].arn
    error_message = "the trigger topic must use the module's customer managed key, never alias/aws/sns"
  }

  assert {
    condition     = aws_kms_key.sns[0].enable_key_rotation && aws_kms_alias.sns[0].name == "alias/pay-stage-use1-dr-failover-sns"
    error_message = "the topic key rotates and has the <name>-sns alias"
  }

  assert {
    condition = length([
      for st in jsondecode(aws_kms_key.sns[0].policy).Statement : st
      if try(st.Principal.Service, "") == "cloudwatch.amazonaws.com" &&
      st.Effect == "Allow" &&
      contains(st.Action, "kms:Decrypt") && contains(st.Action, "kms:GenerateDataKey*") &&
      try(st.Condition.StringEquals["aws:SourceAccount"], "") == var.account_id
    ]) == 1
    error_message = "the key policy grants CloudWatch Decrypt and GenerateDataKey* limited to the source account"
  }

  assert {
    condition = length([
      for st in jsondecode(aws_kms_key.sns[0].policy).Statement : st
      if try(st.Principal.AWS, "") == "arn:aws:iam::111111111111:root" && st.Action == "kms:*"
    ]) == 1
    error_message = "the account root administers the key"
  }
}

run "existing_topic_key_is_used" {
  command = apply

  variables {
    sns_kms_key_arn = "arn:aws:kms:us-east-1:111111111111:key/77777777-8888-9999-aaaa-bbbbbbbbbbbb"
  }

  assert {
    condition     = length(aws_kms_key.sns) == 0 && length(aws_kms_alias.sns) == 0 && aws_sns_topic.failover.kms_master_key_id == var.sns_kms_key_arn
    error_message = "a supplied key replaces the module key"
  }
}

run "aws_managed_topic_key_rejected" {
  command = plan

  variables {
    sns_kms_key_arn = "alias/aws/sns"
  }

  expect_failures = [var.sns_kms_key_arn]
}

run "short_alarm_window_rejected" {
  command = plan

  variables {
    alarm_evaluation_periods = 1
  }

  expect_failures = [var.alarm_evaluation_periods]
}

run "warm_standby_adds_no_writers" {
  command = plan

  assert {
    condition     = jsondecode(aws_lambda_function.failover.environment[0].variables.SWITCH_WRITER_CLASSES) == {} && aws_lambda_function.failover.environment[0].variables.COMPUTE_BUILD_URL == ""
    error_message = "without pilot-light inputs the function only promotes"
  }

  assert {
    condition     = !anytrue([for s in jsondecode(aws_iam_role_policy.function.policy).Statement : s.Sid == "AddSwitchWriters" || s.Sid == "ComputeBuildToken"])
    error_message = "no instance creation or token rights without pilot-light inputs"
  }
}

run "pilot_light_adds_writers_and_starts_the_compute_build" {
  command = plan

  variables {
    switch_writer_instance_classes = { "cell-0" = "db.r7g.12xlarge", "cell-1" = "db.r7g.12xlarge", locker = "db.r7g.4xlarge" }
    compute_build = {
      dispatch_url     = "https://api.github.com/repos/example/platform/actions/workflows/dr-build-compute.yml/dispatches"
      token_secret_arn = "arn:aws:secretsmanager:us-east-1:111111111111:secret:pay-stage-dr-build-token"
    }
  }

  assert {
    condition     = jsondecode(aws_lambda_function.failover.environment[0].variables.SWITCH_WRITER_CLASSES).locker == "db.r7g.4xlarge" && startswith(aws_lambda_function.failover.environment[0].variables.COMPUTE_BUILD_URL, "https://")
    error_message = "writer classes and the build URL reach the function"
  }

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.function.policy).Statement :
      alltrue([for r in s.Resource : strcontains(r, ":pay-stage-use1-aurora-")])
      if s.Sid == "AddSwitchWriters"
    ]) && anytrue([for s in jsondecode(aws_iam_role_policy.function.policy).Statement : s.Sid == "ComputeBuildToken" && s.Resource == var.compute_build.token_secret_arn])
    error_message = "writers only in this region's project clusters; the token is the one secret"
  }
}

run "switch_writers_must_cover_every_cell" {
  command = plan

  variables {
    switch_writer_instance_classes = { "cell-0" = "db.r7g.12xlarge" }
  }

  expect_failures = [var.switch_writer_instance_classes]
}
