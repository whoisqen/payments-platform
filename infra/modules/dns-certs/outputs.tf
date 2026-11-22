output "zone_id" {
  value       = aws_route53_zone.this.zone_id
  description = "Hosted zone ID."
}

output "name_servers" {
  value       = aws_route53_zone.this.name_servers
  description = "Name servers to delegate to from the parent zone."
}

output "certificate_arns" {
  value       = { for k, v in aws_acm_certificate_validation.this : k => v.certificate_arn }
  description = "ARNs of validated certificates by name."
}
