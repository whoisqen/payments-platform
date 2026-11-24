output "role_arn" {
  description = "Role of External Secrets Operator in the central cluster (Pod Identity)."
  value       = aws_iam_role.external_secrets.arn
}

output "secret_arns" {
  description = "ARN of each secret created here, by name without the prefix (for example sentry/redis-password)."
  value       = { for k, s in aws_secretsmanager_secret.this : k => s.arn }
}

output "secret_names" {
  description = "Full name of each secret created here, by name without the prefix."
  value       = { for k, s in aws_secretsmanager_secret.this : k => s.name }
}
