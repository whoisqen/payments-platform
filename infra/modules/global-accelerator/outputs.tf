output "accelerator_arn" {
  value       = aws_globalaccelerator_accelerator.this.id
  description = "Accelerator ARN."
}

output "dns_name" {
  value       = aws_globalaccelerator_accelerator.this.dns_name
  description = "Accelerator DNS name, the target of the public Route 53 alias."
}

output "static_ips" {
  value       = flatten([for s in aws_globalaccelerator_accelerator.this.ip_sets : s.ip_addresses])
  description = "Anycast IPs of the accelerator."
}

output "endpoint_group_arns" {
  value       = { for r, g in aws_globalaccelerator_endpoint_group.this : r => g.arn }
  description = "Endpoint group ARNs by region."
}
