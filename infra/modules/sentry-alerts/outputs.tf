output "rule_ids" {
  description = "Issue alert rule id by <project>/<critical|high>."
  value       = { for k, r in sentry_issue_alert.this : k => r.id }
}
