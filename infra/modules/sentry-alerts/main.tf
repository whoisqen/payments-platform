data "sentry_all_projects" "this" {
  count = var.projects == null ? 1 : 0

  organization = var.organization
}

locals {
  projects = var.projects == null ? sort(tolist(data.sentry_all_projects.this[0].project_slugs)) : var.projects

  # critical: every fatal event of a new, regressed or reappeared issue; high: error issues that Sentry rates high priority.
  rules = {
    critical = {
      level      = "fatal"
      conditions = [{ first_seen_event = {} }, { regression_event = {} }, { reappeared_event = {} }]
    }
    high = {
      level      = "error"
      conditions = [{ new_high_priority_issue = {} }, { existing_high_priority_issue = {} }]
    }
  }

  alerts = merge([for p in local.projects : { for r, v in local.rules : "${p}/${r}" => merge(v, { project = p, severity = r }) }]...)
}

resource "sentry_issue_alert" "this" {
  for_each = local.alerts

  organization = var.organization
  project      = each.value.project
  name         = "${each.value.severity}: ${each.value.level} to ${var.slack_channel}"
  action_match = "any"
  filter_match = "all"
  frequency    = var.frequency_minutes

  conditions_v2 = each.value.conditions

  filters_v2 = [{
    level = { match = "EQUAL", level = each.value.level }
  }]

  actions_v2 = [{
    slack_notify_service = {
      workspace = var.slack_workspace_id
      channel   = var.slack_channel
      tags      = ["environment", "level", "release"]
      notes     = "${each.value.severity} issue of ${each.value.project}"
    }
  }]
}
