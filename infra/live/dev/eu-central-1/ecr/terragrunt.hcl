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
      "ebs-nodes" = "arn:aws:kms:eu-central-1:000000000000:key/mrk-ebs-nodes"
      "logs"      = "arn:aws:kms:eu-central-1:000000000000:key/mrk-logs"
      "shared"    = "arn:aws:kms:eu-central-1:000000000000:key/mrk-shared"
      "locker"    = "arn:aws:kms:eu-central-1:000000000000:key/mrk-locker"
      "backup"    = "arn:aws:kms:eu-central-1:000000000000:key/mrk-backup"
      "cell-0"    = "arn:aws:kms:eu-central-1:000000000000:key/mrk-cell-0"
      "cell-1"    = "arn:aws:kms:eu-central-1:000000000000:key/mrk-cell-1"
      "cell-2"    = "arn:aws:kms:eu-central-1:000000000000:key/mrk-cell-2"
      "cell-3"    = "arn:aws:kms:eu-central-1:000000000000:key/mrk-cell-3"
      "spare"     = "arn:aws:kms:eu-central-1:000000000000:key/mrk-spare"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  repositories        = ["router", "locker", "drainer", "scheduler", "control-center"]
  kms_key_arn         = dependency.kms.outputs.key_arns["shared"]
  replication_regions = ["us-east-1", "us-east-2"]
}
