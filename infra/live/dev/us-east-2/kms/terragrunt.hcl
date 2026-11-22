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
      "ebs-nodes" = "arn:aws:kms:eu-central-1:000000000000:key/mrk-ebs-nodes"
      "logs" = "arn:aws:kms:eu-central-1:000000000000:key/mrk-logs"
      "shared" = "arn:aws:kms:eu-central-1:000000000000:key/mrk-shared"
      "locker" = "arn:aws:kms:eu-central-1:000000000000:key/mrk-locker"
      "backup" = "arn:aws:kms:eu-central-1:000000000000:key/mrk-backup"
      "cell-0" = "arn:aws:kms:eu-central-1:000000000000:key/mrk-cell-0"
      "cell-1" = "arn:aws:kms:eu-central-1:000000000000:key/mrk-cell-1"
      "cell-2" = "arn:aws:kms:eu-central-1:000000000000:key/mrk-cell-2"
      "cell-3" = "arn:aws:kms:eu-central-1:000000000000:key/mrk-cell-3"
      "spare" = "arn:aws:kms:eu-central-1:000000000000:key/mrk-spare"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  is_replica       = true
  primary_key_arns = dependency.primary.outputs.key_arns
}
