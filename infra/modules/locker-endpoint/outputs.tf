output "host" {
  value       = local.host
  description = "DNS name the router and scheduler call: <service>.<namespace>.svc.locker.<cluster_domain>."
}

output "url" {
  value       = "http://${local.host}:${var.port}"
  description = "Locker URL of the cells (ROUTER__LOCKER__HOST)."
}

output "target_group_arn" {
  value       = aws_lb_target_group.this.arn
  description = "Target group of the TargetGroupBinding in the locker cluster."
}

output "load_balancer_security_group_id" {
  value       = aws_security_group.lb.id
  description = "Security group of the load balancer; locker pods admit it on port."
}

output "zone_id" {
  value       = aws_route53_zone.this.zone_id
  description = "Private zone locker.<cluster_domain>."
}
