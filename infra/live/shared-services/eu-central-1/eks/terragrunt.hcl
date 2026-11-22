include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/compute/eks.hcl"
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

inputs = {
  component           = "eks-ci"
  vpc_id              = dependency.vpc.outputs.vpc_id
  vpc_cidr_block      = dependency.vpc.outputs.vpc_cidr_block
  subnet_ids          = dependency.vpc.outputs.subnet_ids["private"]
  secrets_kms_key_arn = dependency.kms.outputs.key_arns["shared"]
  logs_kms_key_arn    = dependency.kms.outputs.key_arns["logs"]
  ebs_kms_key_arn     = dependency.kms.outputs.key_arns["ebs-nodes"]
  tags = {
    team        = "platform"
    owner       = include.envcommon.locals.env_cfg.owner
    pci-scope   = "out-of-scope"
    data-class  = "internal"
    backup-tier = "none"
  }
}
