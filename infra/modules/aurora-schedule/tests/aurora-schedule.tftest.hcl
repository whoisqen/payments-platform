mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/pay-dev-euc1-aurora-schedule" }
  }
}

variables {
  name_prefix         = "pay"
  env                 = "dev"
  region_short        = "euc1"
  region              = "eu-central-1"
  account_id          = "111111111111"
  cluster_identifiers = ["pay-dev-euc1-aurora-cell-0", "pay-dev-euc1-aurora-locker"]
  tags = {
    team = "platform", owner = "platform@example.com", pci-scope = "cde", data-class = "internal", backup-tier = "none"
  }
}

run "each_cluster_gets_a_stop_and_a_start" {
  command = plan

  assert {
    condition     = length(aws_scheduler_schedule.this) == 4 && aws_scheduler_schedule.this["stop-pay-dev-euc1-aurora-locker"].target[0].arn == "arn:aws:scheduler:::aws-sdk:rds:stopDBCluster"
    error_message = "one stop and one start schedule per cluster"
  }

  assert {
    condition     = jsondecode(aws_scheduler_schedule.this["start-pay-dev-euc1-aurora-cell-0"].target[0].input).DbClusterIdentifier == "pay-dev-euc1-aurora-cell-0" && aws_scheduler_schedule.this["start-pay-dev-euc1-aurora-cell-0"].schedule_expression == "cron(0 8 ? * MON-FRI *)"
    error_message = "the start targets its cluster at the start of the window"
  }

  assert {
    condition     = toset(jsondecode(aws_iam_role_policy.scheduler.policy).Statement[0].Resource) == toset(["arn:aws:rds:eu-central-1:111111111111:cluster:pay-dev-euc1-aurora-cell-0", "arn:aws:rds:eu-central-1:111111111111:cluster:pay-dev-euc1-aurora-locker"])
    error_message = "the role may stop and start only the listed clusters"
  }
}

run "stage_is_rejected" {
  command = plan

  variables {
    env = "stage"
  }

  expect_failures = [var.env]
}
