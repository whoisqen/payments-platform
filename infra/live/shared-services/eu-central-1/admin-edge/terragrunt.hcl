include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/observability/admin-edge.hcl"
  expose = true
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id = "vpc-00000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "eks" {
  config_path = "../central/eks"

  mock_outputs = {
    cluster_name = "pay-shared-services-euc1-central"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "spoke_vpc_dev_euc1" {
  config_path = "../../../dev/eu-central-1/vpc"

  mock_outputs                            = { vpc_id = "vpc-00000001" }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "spoke_vpc_stage_euc1" {
  config_path = "../../../stage/eu-central-1/vpc"

  mock_outputs                            = { vpc_id = "vpc-00000002" }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "spoke_vpc_prod_euc1" {
  config_path = "../../../prod/eu-central-1/vpc"

  mock_outputs                            = { vpc_id = "vpc-00000003" }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "spoke_vpc_prod_use1" {
  config_path = "../../../prod/us-east-1/vpc"

  mock_outputs                            = { vpc_id = "vpc-00000004" }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

locals {
  hub = read_terragrunt_config("${get_repo_root()}/infra/live/_envcommon/hub-network.hcl").locals
}

# Add the VPC of the administrators' access path to vpc_ids when it is not the VPC of the central cluster.
# nlb_security_group_id goes into the aws-load-balancer-security-groups annotation of every internal Gateway and intake Service.
inputs = {
  cluster_name = dependency.eks.outputs.cluster_name
  vpc_ids      = [dependency.vpc.outputs.vpc_id]
  spoke_vpcs = { for k, s in local.hub.spokes : k => {
    region = s.region
    vpc_id = {
      dev-euc1   = dependency.spoke_vpc_dev_euc1.outputs.vpc_id
      stage-euc1 = dependency.spoke_vpc_stage_euc1.outputs.vpc_id
      prod-euc1  = dependency.spoke_vpc_prod_euc1.outputs.vpc_id
      prod-use1  = dependency.spoke_vpc_prod_use1.outputs.vpc_id
    }[k]
  } }
  nlb_security_group = {
    vpc_id      = dependency.vpc.outputs.vpc_id
    spoke_cidrs = flatten([for s in values(local.hub.spokes) : s.cidrs])
    local_cidrs = [local.hub.hub_vpc_cidr]
  }
}
