include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/compute/karpenter.hcl"
  expose = true
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id         = "vpc-00000000"
    vpc_cidr_block = "10.140.0.0/16"
    subnet_ids = {
      public  = ["subnet-a00000000", "subnet-a10000000", "subnet-a20000000"]
      private = ["subnet-b00000000", "subnet-b10000000", "subnet-b20000000"]
      data    = ["subnet-c00000000", "subnet-c10000000", "subnet-c20000000"]
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate"]
}

dependency "kms" {
  config_path = "../kms"

  mock_outputs = {
    key_arns = {
      "ebs-nodes"     = "arn:aws:kms:eu-central-1:000000000000:key/mrk-ebs-nodes"
      "logs"          = "arn:aws:kms:eu-central-1:000000000000:key/mrk-logs"
      "shared"        = "arn:aws:kms:eu-central-1:000000000000:key/mrk-shared"
      "runners-cache" = "arn:aws:kms:eu-central-1:000000000000:key/mrk-runners-cache"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate"]
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_name           = "pay-shared-services-euc1-eks-ci"
    node_security_group_id = "sg-00000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate"]
}

inputs = {
  cluster_name                = dependency.eks.outputs.cluster_name
  subnet_ids                  = dependency.vpc.outputs.subnet_ids["private"]
  security_group_ids          = [dependency.eks.outputs.node_security_group_id]
  ebs_kms_key_arn             = dependency.kms.outputs.key_arns["ebs-nodes"]
  enabled_pools               = include.envcommon.locals.env_cfg.enabled_pools
  pull_through_cache_prefixes = keys(include.envcommon.locals.env_cfg.pull_through_cache)
  extra_node_tags = {
    environment = include.root.locals.env
    cell        = include.root.locals.cell
    component   = "karpenter-nodes"
    managed-by  = "argocd"
    repo        = "infra/modules/karpenter"
    cost-center = include.envcommon.locals.env_cfg.cost_center
  }
  tags = {
    team        = "platform"
    owner       = include.envcommon.locals.env_cfg.owner
    pci-scope   = "out-of-scope"
    data-class  = "internal"
    backup-tier = "none"
  }
}
