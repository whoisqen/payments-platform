output "key_arn" {
  value       = local.is_replica ? aws_kms_replica_key.replica[0].arn : aws_kms_key.primary[0].arn
  description = "ARN of the key or replica key."
}

output "key_id" {
  value       = local.is_replica ? aws_kms_replica_key.replica[0].key_id : aws_kms_key.primary[0].key_id
  description = "ID of the key; a replica shares the ID of its primary."
}

output "alias_name" {
  value       = aws_kms_alias.this.name
  description = "Alias in the form alias/pay-<env>-<region-short>-<component>."
}
