include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/data/data-access.hcl"
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

dependency "eks_cell_0" {
  config_path = "../../cell-0/eks"

  mock_outputs = {
    cluster_name           = "pay-mock-euc1-eks"
    cluster_arn            = "arn:aws:eks:eu-central-1:000000000000:cluster/pay-mock-euc1-eks"
    locker_pod_security_group_id = "sg-00000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "eks_cell_1" {
  config_path = "../../cell-1/eks"

  mock_outputs = {
    cluster_name           = "pay-mock-euc1-eks"
    cluster_arn            = "arn:aws:eks:eu-central-1:000000000000:cluster/pay-mock-euc1-eks"
    locker_pod_security_group_id = "sg-00000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "eks_cell_2" {
  config_path = "../../cell-2/eks"

  mock_outputs = {
    cluster_name           = "pay-mock-euc1-eks"
    cluster_arn            = "arn:aws:eks:eu-central-1:000000000000:cluster/pay-mock-euc1-eks"
    locker_pod_security_group_id = "sg-00000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "eks_cell_3" {
  config_path = "../../cell-3/eks"

  mock_outputs = {
    cluster_name           = "pay-mock-euc1-eks"
    cluster_arn            = "arn:aws:eks:eu-central-1:000000000000:cluster/pay-mock-euc1-eks"
    locker_pod_security_group_id = "sg-00000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "eks_spare" {
  config_path = "../../spare/eks"

  mock_outputs = {
    cluster_name           = "pay-mock-euc1-eks"
    cluster_arn            = "arn:aws:eks:eu-central-1:000000000000:cluster/pay-mock-euc1-eks"
    locker_pod_security_group_id = "sg-00000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  component       = "data-locker"
  vpc_id          = dependency.vpc.outputs.vpc_id
  data_subnet_ids = dependency.vpc.outputs.subnet_ids["data"]
  client_security_group_ids = [
    dependency.eks_cell_0.outputs.locker_pod_security_group_id,
    dependency.eks_cell_1.outputs.locker_pod_security_group_id,
    dependency.eks_cell_2.outputs.locker_pod_security_group_id,
    dependency.eks_cell_3.outputs.locker_pod_security_group_id,
    dependency.eks_spare.outputs.locker_pod_security_group_id,
  ]
  stores = {
    aurora       = { port = 5432, clients = "aurora-proxy" }
    # Clients are the locker pod security groups only (PCI DSS 1.4); no cell-wide node group is listed.
    aurora-proxy = { port = 5432, clients = "workload" }
  }
}
