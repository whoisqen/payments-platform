output "role_arn" {
  value       = aws_iam_role.this.arn
  description = "role_arn of this environment in config/admin-agent.yaml."
}
