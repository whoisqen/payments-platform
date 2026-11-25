output "lock_table_name" {
  description = "DynamoDB table that holds one lock record per cell."
  value       = aws_dynamodb_table.lock.name
}

output "alarm_arn" {
  description = "Alarm that starts the failover."
  value       = aws_cloudwatch_metric_alarm.working_region_down.arn
}

output "function_name" {
  description = "Lambda function that runs scripts/dr/failover.py in warm mode."
  value       = aws_lambda_function.failover.function_name
}

output "sns_kms_key_arn" {
  description = "Customer managed key of the failover trigger topic."
  value       = local.sns_kms_key_arn
}
