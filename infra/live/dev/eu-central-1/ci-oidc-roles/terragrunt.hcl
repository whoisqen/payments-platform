include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/security/ci-oidc-roles.hcl"
  expose = true
}

# The account has no GitHub OIDC provider yet, so this stack creates it.
inputs = {
  create_oidc_provider = true
}
