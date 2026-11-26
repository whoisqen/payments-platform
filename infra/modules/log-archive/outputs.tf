output "bucket_name" {
  description = "Log archive bucket."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "ARN of the log archive bucket."
  value       = aws_s3_bucket.this.arn
}

output "kms_key_arn" {
  description = "Key that the trail, Config and VPC Flow Logs encrypt with."
  value       = aws_kms_key.this.arn
}

output "prefixes" {
  description = "Key prefix of each log source."
  value       = var.prefixes
}

output "flow_logs_destination_arn" {
  description = "log_destination for aws_flow_log with log_destination_type s3."
  value       = "${aws_s3_bucket.this.arn}/${var.prefixes.flow_logs}/"
}

output "access_log_bucket_name" {
  description = "Bucket of the server access logs of the archive."
  value       = aws_s3_bucket.access.bucket
}
