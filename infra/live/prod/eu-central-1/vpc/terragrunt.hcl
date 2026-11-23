include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/foundation/vpc.hcl"
  expose = true
}

inputs = {
  cidr_block = include.envcommon.locals.env_cfg.vpc_cidrs["eu-central-1"]
  azs        = include.envcommon.locals.env_cfg.azs["eu-central-1"]
  subnet_cidrs = {
    public  = [for i in range(3) : cidrsubnet(include.envcommon.locals.env_cfg.vpc_cidrs["eu-central-1"], 8, 99 + i)]
    private = [for i in range(3) : cidrsubnet(include.envcommon.locals.env_cfg.vpc_cidrs["eu-central-1"], 3, i)]
    data    = [for i in range(3) : cidrsubnet(include.envcommon.locals.env_cfg.vpc_cidrs["eu-central-1"], 8, 96 + i)]
  }
  enable_egress_route       = try(include.envcommon.locals.env_cfg.transit_gateway_ids[include.root.locals.region], null) != null
  egress_transit_gateway_id = try(include.envcommon.locals.env_cfg.transit_gateway_ids[include.root.locals.region], null)
}
