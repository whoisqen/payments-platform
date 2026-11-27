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

dependency "eks_cell_0" {
  config_path = "../../cell-0/eks"

  mock_outputs = {
    cluster_name           = "pay-mock-euc1-eks-cell-0"
    cluster_arn            = "arn:aws:eks:eu-central-1:000000000000:cluster/pay-mock-euc1-eks-cell-0"
    node_security_group_id = "sg-00000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "eks_spare" {
  config_path = "../../spare/eks"

  mock_outputs = {
    cluster_name           = "pay-mock-euc1-eks-spare"
    cluster_arn            = "arn:aws:eks:eu-central-1:000000000000:cluster/pay-mock-euc1-eks-spare"
    node_security_group_id = "sg-00000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

# Brokers take IAM-authenticated TLS (9098) from the cell nodes (the Hyperswitch producers) and the analytics nodes (ClickHouse Kafka engine) only.
inputs = {
  component       = "analytics-msk"
  vpc_id          = dependency.vpc.outputs.vpc_id
  data_subnet_ids = dependency.vpc.outputs.subnet_ids["data"]
  client_security_group_ids = [
    dependency.eks.outputs.node_security_group_id,
    dependency.eks_cell_0.outputs.node_security_group_id,
    dependency.eks_spare.outputs.node_security_group_id,
  ]
  stores = {
    msk = { port = 9098, clients = "workload" }
  }
}
