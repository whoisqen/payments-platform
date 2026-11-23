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

run "short_alarm_window_rejected" {
  command = plan

  variables {
    alarm_evaluation_periods = 1
  }

  expect_failures = [var.alarm_evaluation_periods]
}
