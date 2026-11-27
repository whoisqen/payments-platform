output "document_names" {
  value       = [for d in aws_ssm_document.this : d.name]
  description = "cell-copy-merchant and cell-verify-merchant, the names scripts/cells/migrate-merchant.py starts."
}

output "automation_role_arn" {
  value       = aws_iam_role.automation.arn
  description = "Default AutomationAssumeRole of the documents."
}

output "function_name" {
  value       = local.function_name
  description = "Copy function the documents invoke."
}
