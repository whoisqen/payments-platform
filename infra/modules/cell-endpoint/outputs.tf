output "host" {
  value       = local.host
  description = "DNS name the edge calls: router.payments.svc.<cell>.<cluster_domain>."
}

output "target_group_arn" {
  value       = aws_lb_target_group.this.arn
  description = "Target group of the TargetGroupBinding of the router gateway in the cell cluster."
}

output "controller_role_arn" {
  value       = aws_iam_role.controller.arn
  description = "Role the load balancer controller of the cell cluster uses for this target group."
}

output "zone_id" {
  value       = aws_route53_zone.this.zone_id
  description = "Private zone <cell>.<cluster_domain>."
}
