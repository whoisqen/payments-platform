output "endpoint" {
  description = "Host name of the VPC endpoint of the central log domain (opensearch.url of the admin agent of this environment)."
  value       = aws_opensearch_vpc_endpoint.this.endpoint
}

output "security_group_id" {
  description = "Security group of the endpoint."
  value       = aws_security_group.this.id
}
