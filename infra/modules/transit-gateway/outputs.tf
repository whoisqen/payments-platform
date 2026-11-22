output "transit_gateway_id" {
  value       = aws_ec2_transit_gateway.this.id
  description = "Transit gateway ID, used by the vpc module for the egress route."
}

output "route_table_ids" {
  value       = { for k, rt in aws_ec2_transit_gateway_route_table.this : k => rt.id }
  description = "Transit gateway route tables by name."
}

output "attachment_ids" {
  value       = { for k, a in aws_ec2_transit_gateway_vpc_attachment.this : k => a.id }
  description = "VPC attachments by name."
}
