output "role_arn" {
  description = "Role FIS assumes; the EKS access entry for pod actions maps it to the fis-experiment Kubernetes user."
  value       = aws_iam_role.fis.arn
}

output "log_group_arn" {
  description = "Log group of the experiments."
  value       = aws_cloudwatch_log_group.fis.arn
}

output "template_ids" {
  description = "Experiment name => FIS template id; empty in prod unless allow_prod."
  value       = { for k, t in aws_fis_experiment_template.this : k => t.id }
}

output "memorydb_failover_document_arn" {
  description = "SSM Automation document that fails over a MemoryDB shard."
  value       = aws_ssm_document.memorydb_failover.arn
}
