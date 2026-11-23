output "secret_names" {
  description = "Secrets Manager names of the GitHub App credentials per pool; the values are set outside Terraform."
  value       = { for n, s in aws_secretsmanager_secret.github_app : n => s.name }
}

output "asg_names" {
  description = "Auto Scaling group of each pool."
  value       = { for n, g in aws_autoscaling_group.pool : n => g.name }
}

output "runner_role_arns" {
  description = "Instance role of each pool."
  value       = { for n, r in aws_iam_role.runner : n => r.arn }
}

output "runs_on_labels" {
  description = "Runner label that jobs use in runs-on, per pool."
  value       = { for n in local.pool_names : n => n }
}

output "github_push_role_arn" {
  description = "Role that GitHub Actions assumes on main and release branches to push images."
  value       = aws_iam_role.github_push.arn
}

output "cache_bucket_name" {
  description = "Build cache bucket."
  value       = aws_s3_bucket.cache.bucket
}

output "cache_kms_key_arn" {
  description = "KMS key of the build cache."
  value       = aws_kms_key.cache.arn
}
