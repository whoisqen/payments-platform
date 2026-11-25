output "policy_ids" {
  description = "Policy ids keyed by document name."
  value       = { for k, p in aws_organizations_policy.this : k => p.id }
}

output "policy_types" {
  description = "Policy type of each document."
  value       = { for k, p in local.files : k => p.type }
}

output "rcp_id" {
  description = "Id of the resource control policy; null when rcp_targets is empty."
  value       = one(aws_organizations_policy.rcp[*].id)
}

output "attachments" {
  description = "Attached policy and target pairs, policy/target."
  value       = sort(concat(keys(local.attachments), [for t in var.rcp_targets : "rcp/${t}"]))
}
