output "table_arn" {
  description = "ARN of the table in the working region."
  value       = aws_dynamodb_table.this.arn
}

output "table_name" {
  description = "Table name, identical in every replica region."
  value       = aws_dynamodb_table.this.name
}

output "deny_recovery_writes_policy_arn" {
  description = "IAM policy that every service role must attach."
  value       = aws_iam_policy.deny_recovery_writes.arn
}
