output "global_cluster_id" {
  description = "Global cluster identifier; recovery stacks pass it as global_cluster_identifier."
  value       = one(aws_rds_global_cluster.this[*].id)
}

output "primary_cluster_arn" {
  description = "ARN of the writer cluster, null in a recovery role."
  value       = one(aws_rds_cluster.primary[*].arn)
}

output "writer_endpoint" {
  description = "Cluster endpoint of the writer, null in a recovery role."
  value       = one(aws_rds_cluster.primary[*].endpoint)
}

output "reader_endpoint" {
  description = "Reader endpoint of the writer cluster, null in a recovery role."
  value       = one(aws_rds_cluster.primary[*].reader_endpoint)
}

output "master_user_secret_arn" {
  description = "RDS-managed master secret, null in a recovery role."
  value       = try(aws_rds_cluster.primary[0].master_user_secret[0].secret_arn, null)
}

output "proxy_endpoint" {
  description = "RDS Proxy endpoint that router and drainer use."
  value       = one(aws_db_proxy.this[*].endpoint)
}

output "secondary_cluster_arns" {
  description = "Headless secondary cluster ARNs keyed by region."
  value       = { for r, c in aws_rds_cluster.secondary : r => c.arn }
}

output "lag_alarm_arns" {
  description = "Global replication lag alarms keyed by region."
  value       = { for r, a in aws_cloudwatch_metric_alarm.global_lag : r => a.arn }
}

output "proxy_auth_secret_arns" {
  description = "Secrets of the extra proxy logins keyed by name; the value is set out of band and mirrored in Vault."
  value       = local.proxy_enabled ? local.proxy_auth_secret_arns : {}
}
