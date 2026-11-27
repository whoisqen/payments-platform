include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/security/argocd-access.hcl"
  expose = true
}

# The role carries the boundary, and its trust names the hub controller role, which must exist first.
dependencies {
  paths = ["../permissions-boundary", "../../../shared-services/eu-central-1/argocd-access"]
}
