output "zone_id" {
  description = "Id of the private zone of the admin tools."
  value       = aws_route53_zone.admin.zone_id
}

output "zone_name" {
  description = "Name of the private zone."
  value       = aws_route53_zone.admin.name
}

output "wildcard_fqdn" {
  description = "Wildcard name that points at the internal NLB."
  value       = local.wildcard
}

output "wildcard_record_created" {
  description = "True once the second step of the apply has added the wildcard alias."
  value       = length(aws_route53_record.wildcard) > 0
}

output "ca_arn" {
  description = "ARN of the private root CA; the issuer of cert-manager points at it."
  value       = aws_acmpca_certificate_authority.root.arn
}

output "role_arns" {
  description = "Pod Identity role ARN by controller (load-balancer-controller, privateca-issuer)."
  value       = { for k, r in aws_iam_role.this : k => r.arn }
}
