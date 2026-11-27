mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }
}

variables {
  name_prefix  = "pay"
  env          = "prod"
  region_short = "use1"
  tags = {
    team          = "platform"
    owner         = "platform@example.com"
    "pci-scope"   = "connected"
    "data-class"  = "internal"
    "backup-tier" = "none"
  }
}

run "document_publishes_metrics_with_30_minute_target" {
  command = plan

  assert {
    condition     = aws_ssm_document.restore_test.document_type == "Automation" && aws_ssm_document.restore_test.name == "pay-prod-use1-restore-test"
    error_message = "The automation document must be named pay-<env>-<region-short>-restore-test."
  }

  assert {
    condition     = jsondecode(aws_ssm_document.restore_test.content).parameters.TargetSeconds.default == "1800"
    error_message = "The restore target must default to 30 minutes."
  }

  assert {
    condition     = length(jsondecode(aws_ssm_document.restore_test.content).mainSteps) == 1
    error_message = "The document has one script step."
  }
}

run "validator_is_passed_to_the_script_and_invoked_by_role" {
  command = plan

  variables {
    validator_lambda_arn = "arn:aws:lambda:us-east-1:111111111111:function:validator"
  }

  assert {
    condition     = jsondecode(aws_ssm_document.restore_test.content).mainSteps[0].inputs.InputPayload.ValidatorArn == var.validator_lambda_arn
    error_message = "The validator ARN must reach the script."
  }

  assert {
    condition     = strcontains(aws_iam_role_policy.automation.policy, "lambda:InvokeFunction")
    error_message = "The automation role must be allowed to invoke the validator."
  }
}

run "rule_matches_both_final_states_of_database_jobs" {
  command = plan

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.restore_finished.event_pattern).detail.status[1] == "FAILED"
    error_message = "Completed and failed restore jobs must both start the automation."
  }
}

run "missing_tags_are_rejected" {
  command = plan

  variables {
    tags = { team = "platform" }
  }

  expect_failures = [var.tags]
}
