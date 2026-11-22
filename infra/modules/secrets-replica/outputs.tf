output "secret_arns" {
  description = "Secret ARNs keyed by component name."
  value       = { for k, s in aws_secretsmanager_secret.this : k => s.arn }
}

output "replica_regions" {
  description = "Regions that hold a replica of every secret."
  value       = keys(var.recovery_regions)
}
