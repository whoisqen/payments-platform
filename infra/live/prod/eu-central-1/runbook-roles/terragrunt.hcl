include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/security/runbook-roles.hcl"
  expose = true
}

# The GitHub OIDC provider of the account comes from ci-oidc-roles.
dependencies {
  paths = ["../ci-oidc-roles", "../permissions-boundary"]
}
