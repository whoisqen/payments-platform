include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/data/backup.hcl"
  expose = true
}

dependency "kms" {
  config_path = "../kms"

  mock_outputs = {
    key_arns = {
      "ebs-nodes" = "arn:aws:kms:eu-central-1:000000000000:key/mrk-ebs-nodes"
      "logs"      = "arn:aws:kms:eu-central-1:000000000000:key/mrk-logs"
      "shared"    = "arn:aws:kms:eu-central-1:000000000000:key/mrk-shared"
      "locker"    = "arn:aws:kms:eu-central-1:000000000000:key/mrk-locker"
      "backup"    = "arn:aws:kms:eu-central-1:000000000000:key/mrk-backup"
      "cell-0"    = "arn:aws:kms:eu-central-1:000000000000:key/mrk-cell-0"
      "spare"     = "arn:aws:kms:eu-central-1:000000000000:key/mrk-spare"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  kms_key_arn = dependency.kms.outputs.key_arns["backup"]
  data_kms_key_arns = [
    dependency.kms.outputs.key_arns["shared"],
    dependency.kms.outputs.key_arns["locker"],
    dependency.kms.outputs.key_arns["cell-0"],
    dependency.kms.outputs.key_arns["spare"],
  ]
}
