locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

# Pilot light (D6, D7): built by the region switch within the RTO, not kept running; excluding a unit does not destroy it.
exclude {
  if                   = !try(local.env_cfg.standby_compute_enabled, get_env("PAY_STANDBY_COMPUTE", "false") == "true")
  actions              = ["all"]
  exclude_dependencies = false
}

include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/shared-clusters/locker-endpoint.hcl"
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
    cluster_name                 = "pay-mock-use1-eks-locker"
    cluster_arn                  = "arn:aws:eks:us-east-1:000000000000:cluster/pay-mock-use1-eks-locker"
    cluster_endpoint             = "https://MOCK.gr7.us-east-1.eks.amazonaws.com"
    certificate_authority_data   = "TU9DSw=="
    argocd_cluster_name          = "pay-mock-use1-locker"
    node_security_group_id       = "sg-00000000"
    locker_pod_security_group_id = "sg-00000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "eks_cell_0" {
  config_path = "../../cell-0/eks"

  mock_outputs = {
    node_security_group_id = "sg-00000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "eks_cell_1" {
  config_path = "../../cell-1/eks"

  mock_outputs = {
    node_security_group_id = "sg-00000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "eks_cell_2" {
  config_path = "../../cell-2/eks"

  mock_outputs = {
    node_security_group_id = "sg-00000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "eks_cell_3" {
  config_path = "../../cell-3/eks"

  mock_outputs = {
    node_security_group_id = "sg-00000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "eks_spare" {
  config_path = "../../spare/eks"

  mock_outputs = {
    node_security_group_id = "sg-00000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  vpc_id                       = dependency.vpc.outputs.vpc_id
  subnet_ids                   = dependency.vpc.outputs.subnet_ids["private"]
  locker_cluster_name          = dependency.eks.outputs.cluster_name
  locker_cluster_arn           = dependency.eks.outputs.cluster_arn
  locker_pod_security_group_id = dependency.eks.outputs.locker_pod_security_group_id
  client_security_group_ids = [
    dependency.eks_cell_0.outputs.node_security_group_id,
    dependency.eks_cell_1.outputs.node_security_group_id,
    dependency.eks_cell_2.outputs.node_security_group_id,
    dependency.eks_cell_3.outputs.node_security_group_id,
    dependency.eks_spare.outputs.node_security_group_id,
  ]
}
