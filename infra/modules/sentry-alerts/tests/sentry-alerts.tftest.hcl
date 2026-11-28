mock_provider "sentry" {
  mock_data "sentry_project_error_monitor" {
    defaults = { id = "4242" }
  }
}

variables {
  organization       = "payments"
  slack_workspace_id = "123456"
  slack_channel      = "#payments-sentry-critical"
  projects           = ["router", "control-center"]
}

run "every_project_sends_fatal_and_high_error_to_slack" {
  command = plan

  assert {
    condition     = toset(keys(sentry_alert.this)) == toset(["router/critical", "router/high", "control-center/critical", "control-center/high"])
    error_message = "two rules per project"
  }

  assert {
    condition = (
      sentry_alert.this["router/critical"].action_filters[0].conditions[0].level.level == 50 &&
      sentry_alert.this["router/high"].action_filters[0].conditions[0].level.level == 40 &&
      sentry_alert.this["router/high"].action_filters[0].conditions[1].issue_priority_greater_or_equal.comparison == 75 &&
      sentry_alert.this["router/high"].monitor_ids == toset(["4242"])
    )
    error_message = "fatal is critical; error with high priority is high"
  }

  assert {
    condition     = alltrue([for r in sentry_alert.this : r.action_filters[0].actions[0].slack.channel_name == "#payments-sentry-critical" && r.action_filters[0].actions[0].slack.integration_id == "123456"])
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
