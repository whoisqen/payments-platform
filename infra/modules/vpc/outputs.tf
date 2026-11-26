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
  description = "Subnet IDs per tier (public, private, data, untrusted), ordered like azs; an unused tier is an empty list."
}

output "private_route_table_ids" {
  value       = [for k in sort(keys(aws_route_table.private)) : aws_route_table.private[k].id]
  description = "Private route tables, one per AZ."
}

output "public_route_table_ids" {
  value       = var.public_route_table_per_az ? [for k in sort(keys(aws_route_table.public_az)) : aws_route_table.public_az[k].id] : [for i in range(length(var.subnet_cidrs.public)) : aws_route_table.public[0].id]
  description = "Route table of each public subnet, ordered like azs (the same table three times unless public_route_table_per_az)."
}

output "private_cidr_blocks" {
  value       = var.subnet_cidrs.private
  description = "CIDRs of the private tier."
}

output "data_route_table_ids" {
  value       = [for k in sort(keys(aws_route_table.data)) : aws_route_table.data[k].id]
  description = "Data route tables, one per AZ."
}

output "endpoint_security_group_id" {
  value       = aws_security_group.endpoints.id
  description = "Security group of the interface endpoints."
}

output "untrusted_cidr_blocks" {
  value       = var.subnet_cidrs.untrusted
  description = "CIDRs of the untrusted tier; the Network Firewall applies the CI allowlist to them (ci_source_cidrs)."
}
