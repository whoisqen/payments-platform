output "route_ids" {
  value = {
    attachment_to_firewall      = { for k, r in aws_route.attachment_to_firewall : k => r.id }
    firewall_to_nat             = { for k, r in aws_route.firewall_to_nat : k => r.id }
    firewall_to_workloads       = { for k, r in aws_route.firewall_to_workloads : k => r.id }
    nat_return_through_firewall = { for k, r in aws_route.nat_return_through_firewall : k => r.id }
  }
  description = "Routes by kind and AZ index (and workload CIDR for the return routes)."
}
