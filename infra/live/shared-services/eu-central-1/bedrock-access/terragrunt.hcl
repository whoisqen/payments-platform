include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/ai/bedrock-access.hcl"
  expose = true
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id         = "vpc-00000000000000000"
    vpc_cidr_block = "10.0.0.0/16"
    subnet_ids = {
      private = ["subnet-00000000000000000", "subnet-11111111111111111"]
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

# The endpoint is reachable from the VPC itself unless ai.endpoint_allowed_cidrs lists more (CI runners, admin access).
inputs = {
  vpc_id                 = dependency.vpc.outputs.vpc_id
  subnet_ids             = dependency.vpc.outputs.subnet_ids["private"]
  endpoint_allowed_cidrs = try(include.envcommon.locals.ai.endpoint_allowed_cidrs, [dependency.vpc.outputs.vpc_cidr_block])
}
