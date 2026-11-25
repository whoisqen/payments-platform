include "root" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("terragrunt.hcl"))}/_envcommon/security/ci-oidc-roles.hcl"
  expose = true
}

# infra/bootstrap created the account's GitHub OIDC provider; ci-runners holds the ECR push role (AWS_ROLE_ECR_PUSH).
# This stack adds the read-only registry role (AWS_ROLE_ECR_READ) and the plan role of the shared-services stacks.
inputs = {
  create_oidc_provider     = false
  oidc_provider_arn        = include.envcommon.locals.env_cfg.github_oidc_provider_arn
  ecr_read_repository_arns = include.envcommon.locals.env_cfg.ecr_repository_arns
}
