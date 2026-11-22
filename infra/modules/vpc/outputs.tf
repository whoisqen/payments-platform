output "vpc_id" {
  value       = aws_vpc.this.id
  description = "VPC ID."
}

output "vpc_cidr_block" {
  value       = aws_vpc.this.cidr_block
  description = "VPC CIDR."
}

output "subnet_ids" {
  value       = { for t in local.tiers : t => [for i in range(length(var.subnet_cidrs[t])) : aws_subnet.this["${t}-${i}"].id] }
  description = "Subnet IDs per tier (public, private, data), ordered like azs."
}

output "private_route_table_ids" {
  value       = [for k in sort(keys(aws_route_table.private)) : aws_route_table.private[k].id]
  description = "Private route tables, one per AZ."
}

output "data_route_table_ids" {
  value       = [for k in sort(keys(aws_route_table.data)) : aws_route_table.data[k].id]
  description = "Data route tables, one per AZ."
}

output "endpoint_security_group_id" {
  value       = aws_security_group.endpoints.id
  description = "Security group of the interface endpoints."
}
