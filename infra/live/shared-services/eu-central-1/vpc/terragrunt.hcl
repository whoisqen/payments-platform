include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/foundation/vpc.hcl"
  expose = true
}

inputs = {
  component  = "vpc"
  cidr_block = include.envcommon.locals.env_cfg.vpc_cidrs["eu-central-1"]
  azs        = include.envcommon.locals.env_cfg.azs["eu-central-1"]
  subnet_cidrs = {
    public  = [for i in range(3) : cidrsubnet(include.envcommon.locals.env_cfg.vpc_cidrs["eu-central-1"], 8, 99 + i)]
    private = [for i in range(3) : cidrsubnet(include.envcommon.locals.env_cfg.vpc_cidrs["eu-central-1"], 3, i)]
    data    = [for i in range(3) : cidrsubnet(include.envcommon.locals.env_cfg.vpc_cidrs["eu-central-1"], 8, 96 + i)]
    # Pull request runners (ci-pr): /22 per AZ after the public /24s, 10.140.104.0/22 to 10.140.115.255.
    untrusted = [for i in range(3) : cidrsubnet(include.envcommon.locals.env_cfg.vpc_cidrs["eu-central-1"], 6, 26 + i)]
  }
  # Second step after the first tgw apply: transit_gateway_id in env.hcl turns on the default routes of the private and untrusted tiers.
  enable_egress_route       = include.envcommon.locals.env_cfg.transit_gateway_id != null
  egress_transit_gateway_id = include.envcommon.locals.env_cfg.transit_gateway_id
  tags = {
    team        = "platform"
    owner       = include.envcommon.locals.env_cfg.owner
    pci-scope   = "out-of-scope"
    data-class  = "internal"
    backup-tier = "none"
  }
}
