output "role_arns" {
  value       = { for k, r in aws_iam_role.this : k => r.arn }
  description = "Pod identity role ARN by service (router, locker, drainer, scheduler, external-secrets)."
}

output "yace_role_arn" {
  value       = one(aws_iam_role.yace[*].arn)
  description = "Pod Identity role of the CloudWatch exporter; null when disabled."
}
