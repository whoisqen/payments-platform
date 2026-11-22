output "domain_arn" {
  description = "ARN of the domain."
  value       = aws_opensearch_domain.this.arn
}

output "endpoint" {
  description = "VPC endpoint of the domain."
  value       = aws_opensearch_domain.this.endpoint
}

output "snapshot_role_arn" {
  description = "Role for the Snapshot Management repository."
  value       = aws_iam_role.snapshot.arn
}
