output "security_group_ids" {
  value       = { for s, g in aws_security_group.this : s => g.id }
  description = "Security group ID by store name."
}

output "db_subnet_group_name" {
  value       = aws_db_subnet_group.this.name
  description = "DB subnet group over the data subnets, for aurora-global."
}
