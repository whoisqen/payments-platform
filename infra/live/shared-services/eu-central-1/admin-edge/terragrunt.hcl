include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/observability/admin-edge.hcl"
  expose = true
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id = "vpc-00000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "eks" {
  config_path = "../central/eks"

  mock_outputs = {
    cluster_name = "pay-shared-services-euc1-central"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

# Add the VPC of the administrators' access path to vpc_ids when it is not the VPC of the central cluster.
inputs = {
  cluster_name = dependency.eks.outputs.cluster_name
  vpc_ids      = [dependency.vpc.outputs.vpc_id]
}
