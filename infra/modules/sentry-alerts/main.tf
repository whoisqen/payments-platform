data "sentry_all_projects" "this" {
  count = var.projects == null ? 1 : 0

  organization = var.organization
}

# The default error monitor that Sentry creates for every project; the alerts below fire on its issues
data "sentry_project_error_monitor" "this" {
  for_each = toset(local.projects)

  organization = var.organization
  project      = each.value
  first        = true
}

locals {
  projects = var.projects == null ? sort(tolist(data.sentry_all_projects.this[0].project_slugs)) : var.projects

  # Sentry levels and priorities as numbers: fatal 50, error 40; priority high 75
  # critical: every fatal event of a new, regressed or escalating issue; high: error issues that Sentry rates high priority.
  rules = {
    critical = { level = "fatal", level_number = 50, min_priority = null }
    high     = { level = "error", level_number = 40, min_priority = 75 }
  }

  alerts = merge([for p in local.projects : { for r, v in local.rules : "${p}/${r}" => merge(v, { project = p, severity = r }) }]...)
}

resource "sentry_alert" "this" {
  for_each = local.alerts

  organization      = var.organization
  name              = "${each.value.severity}: ${each.value.project} ${each.value.level} to ${var.slack_channel}"
  monitor_ids       = [data.sentry_project_error_monitor.this[each.value.project].id]
  frequency_minutes = var.frequency_minutes

  # A new issue, a regression or an escalation starts the evaluation
  trigger_conditions = [{ first_seen_event = {} }, { regression_event = {} }, { reappeared_event = {} }]

  action_filters = [{
    logic_type = "all"
    conditions = concat(
      [{ level = { match = "eq", level = each.value.level_number }, issue_priority_greater_or_equal = null }],
      each.value.min_priority == null ? [] : [{ level = null, issue_priority_greater_or_equal = { comparison = each.value.min_priority } }],
    )
    actions = [{
      slack = {
        integration_id = var.slack_workspace_id
        channel_name   = var.slack_channel
        tags           = "environment,level,release"
        notes          = "${each.value.severity} issue of ${each.value.project}"
      }
    }]
  }]
}

# The rules were sentry_issue_alert before the provider moved issue alerts to sentry_alert
removed {
  from = sentry_issue_alert.this

  lifecycle {
    destroy = true
  }
}
