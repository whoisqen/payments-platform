include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/security/vault-platform.hcl"
  expose = true
}

# One Vault in shared-services serves dev, stage and prod: it runs on the central cluster, next to Argo CD.
dependency "eks" {
  config_path = "../central/eks"

  mock_outputs = {
    cluster_name = "pay-shared-services-euc1-central"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "kms" {
  config_path = "../kms"

  mock_outputs = {
    key_arns = {
      "shared" = "arn:aws:kms:eu-central-1:000000000000:key/mrk-shared"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "snapshots" {
  config_path = "../vault-snapshots"

  mock_outputs = {
    bucket_arns = {
      "eu-central-1" = "arn:aws:s3:::pay-shared-services-euc1-vault-snapshots"
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
