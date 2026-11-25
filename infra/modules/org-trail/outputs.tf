output "trail_arn" {
  description = "ARN of the organization trail."
  value       = aws_cloudtrail.this.arn
}

output "trail_name" {
  description = "Name of the organization trail."
  value       = aws_cloudtrail.this.name
}

output "log_group_name" {
  description = "CloudWatch Logs group of the trail, for metric filters and alarms."
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_kms_key_arn" {
  description = "Key of the log group."
  value       = aws_kms_key.logs.arn
}
