output "firewall_arn" {
  value       = aws_networkfirewall_firewall.this.arn
  description = "Firewall ARN."
}

output "firewall_endpoint_ids" {
  value       = { for s in aws_networkfirewall_firewall.this.firewall_status[0].sync_states : s.availability_zone => s.attachment[0].endpoint_id }
  description = "Firewall endpoint per AZ, the next hop of the routes from the transit gateway."
}

output "egress_public_ips" {
  value       = [for k in sort(keys(aws_eip.nat)) : aws_eip.nat[k].public_ip]
  description = "Static egress IPs to register with every PSP."
}

output "nat_gateway_ids" {
  value       = [for k in sort(keys(aws_nat_gateway.this)) : aws_nat_gateway.this[k].id]
  description = "NAT gateways, one per AZ."
}

output "psp_fence_rule_group_name" {
  description = "Rule group that the failover script edits to fence the region."
  value       = aws_networkfirewall_rule_group.psp_fence.name
}
