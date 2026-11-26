include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/compute/ci-runners.hcl"
  expose = true
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id                     = "vpc-00000000"
    endpoint_security_group_id = "sg-00000000"
    subnet_ids = {
      public    = ["subnet-a00000000", "subnet-a10000000", "subnet-a20000000"]
      private   = ["subnet-b00000000", "subnet-b10000000", "subnet-b20000000"]
      data      = ["subnet-c00000000", "subnet-c10000000", "subnet-c20000000"]
      untrusted = ["subnet-d00000000", "subnet-d10000000", "subnet-d20000000"]
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate"]
}

dependency "kms" {
  config_path = "../kms"

  mock_outputs = {
    key_arns = {
      "ebs-nodes" = "arn:aws:kms:eu-central-1:000000000000:key/mrk-ebs-nodes"
      "shared"    = "arn:aws:kms:eu-central-1:000000000000:key/mrk-shared"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate"]
}

inputs = {
  vpc_id     = dependency.vpc.outputs.vpc_id
  subnet_ids = dependency.vpc.outputs.subnet_ids["private"]
  # The ci-pr pool fails closed until the vpc stack has an untrusted tier routed only through the Network Firewall.
  untrusted_subnet_ids       = dependency.vpc.outputs.subnet_ids["untrusted"]
  endpoint_security_group_id = dependency.vpc.outputs.endpoint_security_group_id
  ebs_kms_key_arn            = dependency.kms.outputs.key_arns["ebs-nodes"]
  tags = {
    team        = "platform"
    owner       = include.envcommon.locals.env_cfg.owner
    pci-scope   = "out-of-scope"
    data-class  = "internal"
    backup-tier = "none"
  }
}
