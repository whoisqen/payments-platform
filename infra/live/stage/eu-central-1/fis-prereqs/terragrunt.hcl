include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/compute/fis-prereqs.hcl"
  expose = true
}

# The msk-broker-loss experiment targets the analytics/msk cluster of stage only.
inputs = {
  msk_cluster_name = try(include.envcommon.locals.chaos.msk_cluster_name, "${include.envcommon.locals.name}-msk")
}
