output "kms_key_alias" {
  description = "Alias of the unseal key (alias/<prefix>-<env>-<region-short>-vault-unseal); the Vault awskms seal uses it."
  value       = module.unseal_key.alias_name
}

output "kms_key_arn" {
  description = "ARN of the unseal key."
  value       = module.unseal_key.key_arn
}

output "server_role_arn" {
  description = "Role of the Vault server pods."
  value       = aws_iam_role.this["server"].arn
}

output "snapshot_role_arn" {
  description = "Role of the Raft snapshot CronJob."
  value       = aws_iam_role.this["snapshot"].arn
}

output "bootstrap_role_arn" {
  description = "Role of the bootstrap Job."
  value       = aws_iam_role.this["bootstrap"].arn
}
