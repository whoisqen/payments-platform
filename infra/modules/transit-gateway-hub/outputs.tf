output "peering_attachment_ids" {
  value       = { for k, a in aws_ec2_transit_gateway_peering_attachment.this : k => a.id }
  description = "Peering attachments by spoke name; each spoke account accepts its own."
}

output "spoke_route_table_ids" {
  value       = { for k, rt in aws_ec2_transit_gateway_route_table.spoke : k => rt.id }
  description = "Hub route table of each peering."
}
