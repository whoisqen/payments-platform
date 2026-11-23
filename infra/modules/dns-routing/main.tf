# HTTPS probe of each regional ingress; the primary check decides when the standby takes over.
resource "aws_route53_health_check" "this" {
  for_each = var.endpoints

  type              = "HTTPS"
  fqdn              = each.value.target_dns
  port              = var.health_check_port
  resource_path     = var.health_check_path
  enable_sni        = true
  request_interval  = var.request_interval
  failure_threshold = var.failure_threshold
}

# Failover routing: the primary answers every query while its check is healthy; the secondary answers only when it is not.
resource "aws_route53_record" "this" {
  for_each = var.endpoints

  zone_id         = var.zone_id
  name            = var.record_name
  type            = "CNAME"
  ttl             = var.record_ttl
  records         = [each.value.target_dns]
  set_identifier  = each.key
  health_check_id = aws_route53_health_check.this[each.key].id

  failover_routing_policy {
    type = each.key == var.primary_key ? "PRIMARY" : "SECONDARY"
  }
}
