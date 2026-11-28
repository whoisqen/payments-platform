output "hub_route_table_id" {
  value       = aws_ec2_transit_gateway_route_table.hub.id
  description = "Route table of the hub peering; it routes only to this environment's VPC."
}

output "peering_attachment_id" {
  value       = aws_ec2_transit_gateway_peering_attachment_accepter.this.transit_gateway_attachment_id
  description = "Accepted peering attachment to the shared-services hub."
}
