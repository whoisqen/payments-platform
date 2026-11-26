include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/foundation/tgw.hcl"
  expose = true
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id         = "vpc-00000000"
    vpc_cidr_block = "10.0.0.0/16"
    subnet_ids = {
      public    = ["subnet-a00000000", "subnet-a10000000", "subnet-a20000000"]
      private   = ["subnet-b00000000", "subnet-b10000000", "subnet-b20000000"]
      data      = ["subnet-c00000000", "subnet-c10000000", "subnet-c20000000"]
      untrusted = ["subnet-d00000000", "subnet-d10000000", "subnet-d20000000"]
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
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

# Two steps, as in the other environments: apply this stack first, then set transit_gateway_id in shared-services/env.hcl so that the vpc
# stack adds the default routes of its private and untrusted tiers through the attachment below.
inputs = {
  route_tables = ["shared", "egress"]
  static_routes = [
    { route_table = "shared", cidr = "0.0.0.0/0", attachment = "egress" },
  ]
  attachments = {
    shared = {
      vpc_id       = dependency.vpc.outputs.vpc_id
      subnet_ids   = dependency.vpc.outputs.subnet_ids["data"]
      route_table  = "shared"
      propagate_to = ["egress"]
    }
    egress = {
      vpc_id         = dependency.egress_vpc.outputs.vpc_id
      subnet_ids     = dependency.egress_vpc.outputs.subnet_ids["data"]
      route_table    = "egress"
      appliance_mode = true
    }
  }
}
