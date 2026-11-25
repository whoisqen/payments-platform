include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/analytics/karpenter.hcl"
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

dependency "kms" {
  config_path = "../../kms"

  mock_outputs = {
    key_arns = {
      "ebs-nodes" = "arn:aws:kms:eu-central-1:000000000000:key/mrk-ebs-nodes"
      "logs"      = "arn:aws:kms:eu-central-1:000000000000:key/mrk-logs"
      "shared"    = "arn:aws:kms:eu-central-1:000000000000:key/mrk-shared"
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

inputs = {
  cluster_name       = dependency.eks.outputs.cluster_name
  ebs_kms_key_arn    = dependency.kms.outputs.key_arns["ebs-nodes"]
  subnet_ids         = dependency.vpc.outputs.subnet_ids["private"]
  security_group_ids = [dependency.eks.outputs.node_security_group_id]
  extra_node_tags = {
    environment = include.root.locals.env
    cell        = include.root.locals.cell
    component   = "karpenter-nodes"
    managed-by  = "argocd"
    repo        = "infra/modules/karpenter"
    cost-center = include.envcommon.locals.env_cfg.cost_center
  }
}
