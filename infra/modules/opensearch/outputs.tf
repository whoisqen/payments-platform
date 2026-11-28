output "domain_arn" {
  description = "ARN of the domain."
  value       = aws_opensearch_domain.this.arn
}

output "domain_name" {
  description = "Name of the domain."
  value       = aws_opensearch_domain.this.domain_name
}

output "endpoint" {
  description = "VPC endpoint of the domain (host name, no scheme)."
  value       = aws_opensearch_domain.this.endpoint
}

output "dashboards_endpoint" {
  description = "Dashboards endpoint of the domain."
  value       = aws_opensearch_domain.this.dashboard_endpoint
}

output "endpoint_account_ids" {
  description = "Accounts authorized to create a VPC endpoint of the domain."
  value       = keys(aws_opensearch_authorize_vpc_endpoint_access.this)
}

output "dashboards_url" {
  description = "Dashboards URL: the custom endpoint when set, else the VPC endpoint."
  value       = local.custom_endpoint ? "https://${var.custom_endpoint.host}/_dashboards" : "https://${aws_opensearch_domain.this.dashboard_endpoint}"
}

output "security_group_id" {
  description = "Security group of the domain."
  value       = aws_security_group.domain.id
}

output "client_security_group_id" {
  description = "Security group a client attaches to reach the domain, for example an ingestion pipeline."
  value       = aws_security_group.client.id
}

output "log_group_name" {
  description = "CloudWatch log group of the error and slow logs."
  value       = aws_cloudwatch_log_group.this.name
}

output "snapshot_role_arn" {
  description = "Role for the Snapshot Management repository; null without a snapshot bucket."
  value       = one(aws_iam_role.snapshot[*].arn)
}
