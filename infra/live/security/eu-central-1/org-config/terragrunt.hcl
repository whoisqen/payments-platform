include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/security/org/org-config.hcl"
  expose = true
}

# The audit account must be the delegated administrator before it can create the stack set and the organization pack.
dependencies {
  paths = ["../../../management/eu-central-1/org-config"]
}

dependency "log_archive" {
  config_path = "../log-archive"

  mock_outputs = {
    bucket_name = include.envcommon.locals.base.log_bucket_name
    kms_key_arn = "arn:aws:kms:${include.envcommon.locals.base.home_region}:${include.envcommon.locals.base.log_archive_account_id}:key/mrk-log-archive"
    prefixes    = { cloudtrail = "cloudtrail", config = "config", flow_logs = "flow-logs" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  delivery_bucket_name = dependency.log_archive.outputs.bucket_name
  delivery_kms_key_arn = dependency.log_archive.outputs.kms_key_arn
  delivery_key_prefix  = dependency.log_archive.outputs.prefixes.config
}
