include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/foundation/kms.hcl"
  expose = true
}

dependency "primary" {
  config_path = "../../eu-central-1/kms"

  mock_outputs = {
    key_arns = {
      "logs" = "arn:aws:kms:eu-central-1:000000000000:key/mrk-logs"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

# Only the edge runs here (panel-edge, waf-edge) and it uses only the logs key; no cell or locker key exists in this region.
inputs = {
  keys             = { logs = include.envcommon.locals.env_cfg.kms_keys["logs"] }
  is_replica       = true
  primary_key_arns = dependency.primary.outputs.key_arns
}
