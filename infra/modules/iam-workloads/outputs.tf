output "role_arns" {
  value       = { for k, r in aws_iam_role.this : k => r.arn }
  description = "Pod identity role ARN by service (router, locker, drainer, scheduler, external-secrets)."
}
