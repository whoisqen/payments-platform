include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/foundation/ecr.hcl"
  expose = true
}

dependency "kms" {
  config_path = "../kms"

  mock_outputs = {
    key_arns = {
      "ebs-nodes"     = "arn:aws:kms:eu-central-1:000000000000:key/mrk-ebs-nodes"
      "logs"          = "arn:aws:kms:eu-central-1:000000000000:key/mrk-logs"
      "shared"        = "arn:aws:kms:eu-central-1:000000000000:key/mrk-shared"
      "runners-cache" = "arn:aws:kms:eu-central-1:000000000000:key/mrk-runners-cache"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate"]
}

# The CI account holds the build cache and the pull-through cache; the images themselves live in the registries of the environments.
inputs = {
  repositories       = []
  kms_key_arn        = dependency.kms.outputs.key_arns["shared"]
  cache_repositories = ["router", "locker", "drainer", "scheduler", "control-center"]
  pull_through_cache = include.envcommon.locals.env_cfg.pull_through_cache
}
