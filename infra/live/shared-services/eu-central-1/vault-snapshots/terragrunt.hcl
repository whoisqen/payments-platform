include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/security/vault-snapshots.hcl"
  expose = true
}

dependency "kms" {
  config_path = "../kms"

  mock_outputs = {
    key_arns = {
      "ebs-nodes" = "arn:aws:kms:eu-central-1:000000000000:key/mrk-ebs-nodes"
      "shared"    = "arn:aws:kms:eu-central-1:000000000000:key/mrk-shared"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "kms_use1" {
  config_path = "../../us-east-1/kms"

  mock_outputs = {
    key_arns = {
      "ebs-nodes" = "arn:aws:kms:us-east-1:000000000000:key/mrk-ebs-nodes"
      "shared"    = "arn:aws:kms:us-east-1:000000000000:key/mrk-shared"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

# The one Vault of the platform: snapshots replicate to the recovery region (two regions, D7).
inputs = {
  kms_key_arn = dependency.kms.outputs.key_arns["shared"]
  recovery_regions = {
    "us-east-1" = { short = "use1", kms_key_arn = dependency.kms_use1.outputs.key_arns["shared"] }
  }
}
