include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/analytics/access.hcl"
  expose = true
}

dependency "vpc" {
  config_path = "../../vpc"

  mock_outputs = {
    vpc_id         = "vpc-00000000"
    vpc_cidr_block = "10.0.0.0/16"
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
    cluster_name           = "pay-mock-euc1-eks-analytics"
    cluster_arn            = "arn:aws:eks:eu-central-1:000000000000:cluster/pay-mock-euc1-eks-analytics"
    node_security_group_id = "sg-00000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

# The domain takes HTTPS only from the analytics nodes, where the indexer consumes events from MSK.
inputs = {
  component                 = "analytics-opensearch"
  vpc_id                    = dependency.vpc.outputs.vpc_id
  data_subnet_ids           = dependency.vpc.outputs.subnet_ids["data"]
  client_security_group_ids = [dependency.eks.outputs.node_security_group_id]
  stores = {
    opensearch = { port = 443, clients = "workload" }
  }
}
