include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/observability/logs-indices.hcl"
  expose = true
}

dependency "domain" {
  config_path = "../opensearch"

  mock_outputs = {
    endpoint = "vpc-pay-mock-logs-000000.eu-central-1.es.amazonaws.com"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "ingestion" {
  config_path = "../ingestion"

  mock_outputs = {
    logstash_role_arn = "arn:aws:iam::000000000000:role/pay-mock-logstash"
    pipeline_role_arn = "arn:aws:iam::000000000000:role/pay-mock-audit-ingest"
    exporter_role_arn = "arn:aws:iam::000000000000:role/pay-mock-os-exporter"
    grafana_role_arn  = "arn:aws:iam::000000000000:role/pay-mock-grafana"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

# SigV4 as the master role; the domain is VPC-only, so plan and apply run from the CI runners inside the shared-services VPC.
generate "opensearch_provider" {
  path      = "opensearch_provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOT
    provider "opensearch" {
      url                 = "https://${dependency.domain.outputs.endpoint}"
      aws_region          = "${include.root.locals.region}"
      sign_aws_requests   = true
      aws_assume_role_arn = "${include.envcommon.inputs.master_user_arn}"
      healthcheck         = false
      sniff               = false
      opensearch_version  = "2.17"
    }
  EOT
}

inputs = {
  app_writer_role_arns   = [dependency.ingestion.outputs.logstash_role_arn]
  audit_writer_role_arns = [dependency.ingestion.outputs.pipeline_role_arn]
  monitor_role_arns      = [dependency.ingestion.outputs.exporter_role_arn]
  grafana_role_arns      = [dependency.ingestion.outputs.grafana_role_arn]
}
