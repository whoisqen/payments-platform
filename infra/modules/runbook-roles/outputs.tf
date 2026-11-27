output "role_arns" {
  value       = { for k, r in aws_iam_role.caller : k => r.arn }
  description = "<prefix>-<env>-glob-runbook-{diagnose,actions}, assumed by the runbook workflows (tools/ci/runbook/runbook.py)."
}

output "exec_role_arns" {
  value       = { for k, r in aws_iam_role.exec : k => r.arn }
  description = "AutomationAssumeRole of each mode: <role>-exec."
}
