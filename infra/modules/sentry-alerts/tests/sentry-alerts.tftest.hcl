mock_provider "sentry" {}

variables {
  organization       = "payments"
  slack_workspace_id = "123456"
  slack_channel      = "#payments-sentry-critical"
  projects           = ["router", "control-center"]
}

run "every_project_sends_fatal_and_high_error_to_slack" {
  command = plan

  assert {
    condition     = toset(keys(sentry_issue_alert.this)) == toset(["router/critical", "router/high", "control-center/critical", "control-center/high"])
    error_message = "two rules per project"
  }

  assert {
    condition = (
      sentry_issue_alert.this["router/critical"].filters_v2[0].level.level == "fatal" &&
      sentry_issue_alert.this["router/high"].filters_v2[0].level.level == "error" &&
      sentry_issue_alert.this["router/high"].conditions_v2[0].new_high_priority_issue != null
    )
    error_message = "fatal is critical; error with high priority is high"
  }

  assert {
    condition     = alltrue([for r in sentry_issue_alert.this : r.actions_v2[0].slack_notify_service.channel == "#payments-sentry-critical" && r.actions_v2[0].slack_notify_service.workspace == "123456"])
    error_message = "every rule posts to the configured channel of the workspace"
  }
}

run "channel_name_is_checked" {
  command = plan

  variables {
    slack_channel = "payments"
  }

  expect_failures = [var.slack_channel]
}
