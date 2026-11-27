output "role_arn" {
  value       = aws_iam_role.this.arn
  description = "<prefix>-<env>-tf-exec, assumed by the provider that infra/live/terragrunt.hcl generates."
}
