include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/compute/fis-experiments.hcl"
  expose = true
}

dependency "kms" {
  config_path = "../kms"

  mock_outputs = {
    key_arns = {
      "logs" = "arn:aws:kms:eu-central-1:000000000000:key/mrk-logs"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

# Prod keeps the role and log group but no template until the owner sets chaos.prod.allow_prod for a game day.
inputs = {
  log_kms_key_arn = dependency.kms.outputs.key_arns["logs"]
  allow_prod      = try(include.envcommon.locals.chaos.allow_prod, false)
}
