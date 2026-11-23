output "document_name" {
  description = "Name of the SSM Automation document of the restore test."
  value       = aws_ssm_document.restore_test.name
}

output "automation_role_arn" {
  description = "Role the automation runs as."
  value       = aws_iam_role.automation.arn
}

output "event_rule_arn" {
  description = "EventBridge rule that starts the automation when a restore job finishes."
  value       = aws_cloudwatch_event_rule.restore_finished.arn
}
