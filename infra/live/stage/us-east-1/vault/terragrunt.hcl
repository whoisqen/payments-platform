include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/security/vault-platform.hcl"
  expose = true
}

locals {
  vault_cell = include.envcommon.locals.env_cfg.cfg.vault.cell
}

dependency "eks" {
  config_path = "../${local.vault_cell}/eks"

  mock_outputs = {
    cluster_name = "pay-mock-use1-eks"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "kms" {
  config_path = "../kms"

  mock_outputs = {
    key_arns = {
      "shared" = "arn:aws:kms:us-east-1:000000000000:key/mrk-shared"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "snapshots" {
  config_path = "../../eu-central-1/vault-snapshots"

  mock_outputs = {
    bucket_arns = {
      "us-east-1" = "arn:aws:s3:::pay-mock-use1-vault-snapshots"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  cluster_name         = dependency.eks.outputs.cluster_name
  snapshot_bucket_arn  = dependency.snapshots.outputs.bucket_arns[include.root.locals.region]
  snapshot_kms_key_arn = dependency.kms.outputs.key_arns["shared"]
  secrets_kms_key_arn  = dependency.kms.outputs.key_arns["shared"]
}
