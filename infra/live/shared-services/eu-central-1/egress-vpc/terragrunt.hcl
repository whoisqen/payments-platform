include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/foundation/egress-vpc.hcl"
  expose = true
}

# CIDR from config/platform.yaml network.shared_services.egress (10.143.0.0/20).
inputs = {
  azs = include.envcommon.locals.env_cfg.azs["eu-central-1"]
}
