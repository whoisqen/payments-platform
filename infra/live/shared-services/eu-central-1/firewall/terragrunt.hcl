include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/foundation/firewall.hcl"
  expose = true
}

dependency "egress_vpc" {
  config_path = "../egress-vpc"

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

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_cidr_block      = "10.140.0.0/16"
    private_cidr_blocks = ["10.140.0.0/19", "10.140.32.0/19", "10.140.64.0/19"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

# Every runner of the VPC (trusted and untrusted tiers) gets the CI allowlist; the trusted pools in the private tier also reach the AWS
# APIs of ci_trusted_domains. Everything else is dropped.
inputs = {
  vpc_id                  = dependency.egress_vpc.outputs.vpc_id
  firewall_subnet_ids     = dependency.egress_vpc.outputs.subnet_ids["private"]
  nat_subnet_ids          = dependency.egress_vpc.outputs.subnet_ids["public"]
  ci_source_cidrs         = [dependency.vpc.outputs.vpc_cidr_block]
  ci_trusted_source_cidrs = dependency.vpc.outputs.private_cidr_blocks
}
