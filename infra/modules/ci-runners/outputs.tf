output "secret_names" {
  description = "Secrets Manager names of the GitHub App keys per scale set; the values are set outside Terraform."
  value       = { for s, secret in aws_secretsmanager_secret.github_app : s => secret.name }
}

output "runner_role_arns" {
  description = "IAM role of each scale set; ARC puts it on the runner service account."
  value       = { for s, r in aws_iam_role.runner : s => r.arn }
}

output "github_push_role_arn" {
  description = "Role that GitHub Actions assumes on main and release branches to push images."
  value       = aws_iam_role.github_push.arn
}

output "external_secrets_role_arn" {
  description = "Role of the External Secrets controller that reads the GitHub App keys."
  value       = aws_iam_role.external_secrets.arn
}

output "cache_bucket_name" {
  description = "Build cache bucket."
  value       = aws_s3_bucket.cache.bucket
}

output "cache_kms_key_arn" {
  description = "KMS key of the build cache."
  value       = aws_kms_key.cache.arn
}
