include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/observability/central-secrets.hcl"
  expose = true
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

dependency "eks" {
  config_path = "../central/eks"

  mock_outputs = {
    cluster_name = "pay-shared-services-euc1-central"
    cluster_arn  = "arn:aws:eks:eu-central-1:000000000000:cluster/pay-shared-services-euc1-central"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  kms_key_arn  = dependency.kms.outputs.key_arns["shared"]
  cluster_name = dependency.eks.outputs.cluster_name
  cluster_arn  = dependency.eks.outputs.cluster_arn
}
