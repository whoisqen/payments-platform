output "vault_arns" {
  description = "Vault ARNs keyed by region."
  value       = { for r, v in aws_backup_vault.this : r => v.arn }
}

output "vault_names" {
  description = "Vault names keyed by region."
  value       = { for r, v in aws_backup_vault.this : r => v.name }
}

output "plan_ids" {
  description = "Backup plan IDs keyed by tier."
  value       = { for t, p in aws_backup_plan.tier : t => p.id }
}

output "backup_role_arn" {
  description = "Service role of the plans and of the restore tests; null without plans."
  value       = one(aws_iam_role.backup[*].arn)
}
