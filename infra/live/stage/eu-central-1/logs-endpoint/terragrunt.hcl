include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/analytics/logs-endpoint.hcl"
  expose = true
}

dependency "vpc" {
  config_path = "../vpc"

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

inputs = {
  vpc_id     = dependency.vpc.outputs.vpc_id
  subnet_ids = dependency.vpc.outputs.subnet_ids["private"]
}
