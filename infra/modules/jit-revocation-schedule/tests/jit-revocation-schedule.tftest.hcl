mock_provider "aws" {}

variables {
  name_prefix       = "pay"
  github_repository = "example-org/payments-platform"
  tags = {
    team = "security", owner = "security@example.com", pci-scope = "connected", data-class = "internal", backup-tier = "none"
  }
}

run "dispatches_the_revocation_workflow_every_15_minutes" {
  command = plan

  assert {
    condition     = aws_cloudwatch_event_rule.schedule.schedule_expression == "rate(15 minutes)"
    error_message = "revocation lags by at most 15 minutes"
  }
  assert {
    condition     = aws_cloudwatch_event_api_destination.dispatch.invocation_endpoint == "https://api.github.com/repos/example-org/payments-platform/actions/workflows/cde-jit-revocation.yml/dispatches"
    error_message = "workflow_dispatch of the revocation workflow"
  }
  assert {
    condition     = jsondecode(aws_cloudwatch_event_target.dispatch.input).ref == "main"
    error_message = "the run uses main"
  }
}
