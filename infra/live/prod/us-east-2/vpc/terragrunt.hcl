include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/foundation/vpc.hcl"
  expose = true
}

inputs = {
  cidr_block = include.envcommon.locals.env_cfg.vpc_cidrs["us-east-2"]
  azs        = include.envcommon.locals.env_cfg.azs["us-east-2"]
  subnet_cidrs = {
    public  = [for i in range(3) : cidrsubnet(include.envcommon.locals.env_cfg.vpc_cidrs["us-east-2"], 8, 99 + i)]
    private = [for i in range(3) : cidrsubnet(include.envcommon.locals.env_cfg.vpc_cidrs["us-east-2"], 3, i)]
    data    = [for i in range(3) : cidrsubnet(include.envcommon.locals.env_cfg.vpc_cidrs["us-east-2"], 8, 96 + i)]
  }
}
