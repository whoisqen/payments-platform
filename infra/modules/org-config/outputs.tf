output "delegated_services" {
  description = "Service principals delegated to the audit account (management mode)."
  value       = sort(keys(aws_organizations_delegated_administrator.this))
}

output "aggregator_arn" {
  description = "Organization aggregator; null in management mode."
  value       = one(aws_config_configuration_aggregator.this[*].arn)
}

output "recorder_stack_set_name" {
  description = "Stack set that deploys the recorders; null when disabled."
  value       = one(aws_cloudformation_stack_set.recorder[*].name)
}

output "conformance_pack_regions" {
  description = "Regions with the organization conformance pack."
  value       = sort(keys(aws_config_organization_conformance_pack.this))
}
