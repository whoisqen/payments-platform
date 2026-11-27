output "rule_arn" {
  value       = aws_cloudwatch_event_rule.schedule.arn
  description = "Schedule of the revocation run."
}

output "connection_name" {
  value       = aws_cloudwatch_event_connection.github.name
  description = "Connection whose API key (Authorization: Bearer <token>) the owner sets in the console."
}

output "dead_letter_queue_arn" {
  value       = aws_sqs_queue.dead_letter.arn
  description = "Dispatches that failed three times; alert on its depth."
}
