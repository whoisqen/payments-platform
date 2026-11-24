output "bucket_names" {
  description = "Bucket name by component (loki, tempo, sentry)."
  value       = { for k, b in aws_s3_bucket.this : k => b.bucket }
}

output "bucket_arns" {
  description = "Bucket ARN by component."
  value       = { for k, b in aws_s3_bucket.this : k => b.arn }
}

output "role_arns" {
  description = "Pod Identity role ARN by component."
  value       = { for k, r in aws_iam_role.this : k => r.arn }
}
