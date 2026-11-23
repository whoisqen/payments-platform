output "record_fqdn" {
  description = "Public API name that clients resolve."
  value       = var.record_name
}

output "health_check_ids" {
  description = "Health check IDs keyed like endpoints."
  value       = { for k, h in aws_route53_health_check.this : k => h.id }
}
