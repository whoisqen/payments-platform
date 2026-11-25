output "permissions_boundary_arn" {
  description = "Boundary for the FIS and automation roles of fis-experiments (input permissions_boundary_arn)."
  value       = aws_iam_policy.boundary.arn
}

output "chaos_stop_alarm_arn" {
  description = "Composite chaos-stop alarm; fis-experiments takes it as the only element of stop_alarm_arns."
  value       = aws_cloudwatch_composite_alarm.chaos_stop.arn
}

output "child_alarm_names" {
  description = "Alarms and ARNs the composite chaos-stop alarm is built from."
  value       = local.child_alarm_names
}

output "fis_access_entry_username" {
  description = "Kubernetes user of the FIS role that the RBAC RoleBinding of pod actions names; null without an access entry."
  value       = one(aws_eks_access_entry.fis[*].user_name)
}

output "msk_reboot_document_arn" {
  description = "SSM Automation document that reboots one MSK broker; null without msk_cluster_name."
  value       = one(aws_ssm_document.msk_reboot_broker[*].arn)
}
