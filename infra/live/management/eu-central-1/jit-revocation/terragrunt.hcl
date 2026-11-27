include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/security/jit-revocation.hcl"
  expose = true
}

# Runs the revocation of expired CDE grants that identity-center (same account) holds.
dependencies {
  paths = ["../identity-center"]
}
