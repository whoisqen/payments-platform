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

inputs = {
  vpc_id = dependency.egress_vpc.outputs.vpc_id
  # One firewall endpoint in dev: the transit gateway routes of every AZ must point at it. NAT gateways and their EIPs stay in three AZs.
  firewall_subnet_ids = slice(dependency.egress_vpc.outputs.subnet_ids["private"], 0, 1)
  nat_subnet_ids      = dependency.egress_vpc.outputs.subnet_ids["public"]
}
