# HTTPS probe of each regional ingress; a failing check drops that region from the latency answer.
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

# Latency routing with a health check: Route 53 skips an unhealthy region, which is the failover.
resource "aws_route53_record" "this" {
  for_each = var.endpoints

  zone_id         = var.zone_id
  name            = var.record_name
  type            = "CNAME"
  ttl             = var.record_ttl
  records         = [each.value.target_dns]
  set_identifier  = each.key
  health_check_id = aws_route53_health_check.this[each.key].id

  latency_routing_policy {
    region = each.value.region
  }
}
