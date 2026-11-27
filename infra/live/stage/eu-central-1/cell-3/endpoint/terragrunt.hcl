include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/compute/cell-endpoint.hcl"
  expose = true
}

dependency "vpc" {
  config_path = "../../vpc"

  mock_outputs = {
    vpc_id = "vpc-00000000"
    subnet_ids = {
      public  = ["subnet-a00000000", "subnet-a10000000", "subnet-a20000000"]
      private = ["subnet-b00000000", "subnet-b10000000", "subnet-b20000000"]
      data    = ["subnet-c00000000", "subnet-c10000000", "subnet-c20000000"]
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_name           = "pay-mock-euc1-eks-cell-3"
    cluster_arn            = "arn:aws:eks:eu-central-1:000000000000:cluster/pay-mock-euc1-eks-cell-3"
    node_security_group_id = "sg-00000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

# The edge cluster of the region is the only caller of this endpoint
dependency "edge" {
  config_path = "../../edge/eks"

  mock_outputs = {
    node_security_group_id = "sg-00000001"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  vpc_id                    = dependency.vpc.outputs.vpc_id
  subnet_ids                = dependency.vpc.outputs.subnet_ids["private"]
  cell_cluster_name         = dependency.eks.outputs.cluster_name
  cell_cluster_arn          = dependency.eks.outputs.cluster_arn
  target_security_group_id  = dependency.eks.outputs.node_security_group_id
  client_security_group_ids = [dependency.edge.outputs.node_security_group_id]
}
