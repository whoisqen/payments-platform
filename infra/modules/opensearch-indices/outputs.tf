output "data_streams" {
  description = "Data stream names: logs-app-<env> by environment, and the audit stream."
  value       = { app = local.app_streams, audit = "logs-audit" }
}

output "ism_policy_ids" {
  description = "ISM policy id by stream class."
  value       = { for k, p in opensearch_ism_policy.this : k => p.policy_id }
}

output "writer_roles" {
  description = "Fine-grained access roles of the writers by stream class."
  value       = { for k, r in opensearch_role.write : k => r.role_name }
}
