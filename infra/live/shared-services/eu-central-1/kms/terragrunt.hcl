include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/foundation/kms.hcl"
  expose = true
}

inputs = {
  tags = {
    team        = "platform"
    owner       = include.envcommon.locals.env_cfg.owner
    pci-scope   = "out-of-scope"
    data-class  = "internal"
    backup-tier = "none"
  }
}
