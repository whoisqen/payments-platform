output "secret_name" {
  description = "Secrets Manager name of the Logstash TLS material (the central-tls remote key under the prefix)."
  value       = aws_secretsmanager_secret.tls.name
}

output "next_rotation" {
  description = "Time after which the next apply issues a new key and certificate."
  value       = time_rotating.certificate.rotation_rfc3339
}

output "zone_id" {
  description = "Private zone of the logs host."
  value       = aws_route53_zone.host.zone_id
}

output "record_created" {
  description = "True once the alias record of the host exists (second step)."
  value       = length(aws_route53_record.host) > 0
}
