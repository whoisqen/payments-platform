output "bucket_names" {
  description = "Bucket name by component (tempo, sentry, vmbackup)."
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

output "yace_role_arn" {
  description = "Pod Identity role of the CloudWatch exporter of the central cluster; null when disabled."
  value       = one(aws_iam_role.yace[*].arn)
}
