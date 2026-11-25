include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/security/org/org-trail.hcl"
  expose = true
}

# The bucket and key live in the log-archive account; that stack applies first.
dependency "log_archive" {
  config_path = "../../../security/eu-central-1/log-archive"

  mock_outputs = {
    bucket_name = "pay-security-euc1-log-archive"
    kms_key_arn = "arn:aws:kms:eu-central-1:000000000002:key/00000000-0000-0000-0000-000000000000"
    prefixes    = { cloudtrail = "cloudtrail", config = "config", flow_logs = "flow-logs" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  s3_bucket_name = dependency.log_archive.outputs.bucket_name
  s3_kms_key_arn = dependency.log_archive.outputs.kms_key_arn
  s3_key_prefix  = dependency.log_archive.outputs.prefixes.cloudtrail
}
