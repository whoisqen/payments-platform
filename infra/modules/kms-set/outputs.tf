output "key_arns" {
  value       = { for k, m in module.key : k => m.key_arn }
  description = "Key or replica key ARN by purpose."
}

output "alias_names" {
  value       = { for k, m in module.key : k => m.alias_name }
  description = "Alias by purpose, pay-<env>-<region-short>-<purpose>."
}
