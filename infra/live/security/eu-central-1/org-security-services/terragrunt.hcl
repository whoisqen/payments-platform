include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/security/org/org-security-services.hcl"
  expose = true
}

# Designation in the management account creates the admin detectors that this stack reads.
dependencies {
  paths = ["../../../management/eu-central-1/org-security-services"]
}
