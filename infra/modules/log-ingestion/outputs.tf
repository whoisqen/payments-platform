output "logstash_role_arn" {
  description = "IRSA role of Logstash (eks.amazonaws.com/role-arn of monitoring/logstash); mapped to logs_app_writer."
  value       = aws_iam_role.logstash.arn
}

output "exporter_role_arn" {
  description = "Pod Identity role of the OpenSearch exporter (monitoring/opensearch-exporter); mapped to logs_monitor."
  value       = aws_iam_role.reader["os-exporter"].arn
}

output "grafana_role_arn" {
  description = "Pod Identity role of Grafana (monitoring/grafana); mapped to logs_grafana."
  value       = aws_iam_role.reader["grafana"].arn
}

output "pipeline_role_arn" {
  description = "Role of the audit ingestion pipelines; mapped to logs_audit_writer and admitted by the log archive."
  value       = aws_iam_role.pipeline.arn
}

output "pipeline_names" {
  description = "OpenSearch Ingestion pipeline by source."
  value       = { for k, p in aws_osis_pipeline.audit : k => p.pipeline_name }
}

output "queue_arns" {
  description = "Queue of each source that the log-archive bucket notifies (log-archive input ingest_notifications)."
  value       = { for k, q in aws_sqs_queue.audit : k => q.arn }
}
