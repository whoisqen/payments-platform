output "bucket_arns" {
  description = "Bucket ARNs keyed by region."
  value       = { for r, b in aws_s3_bucket.this : r => b.arn }
}

output "bucket_names" {
  description = "Bucket names keyed by region."
  value       = { for r, b in aws_s3_bucket.this : r => b.bucket }
}

output "replication_role_arn" {
  description = "Role S3 assumes to replicate; null in a recovery role."
  value       = one(aws_iam_role.replication[*].arn)
}
