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
  # infra/bootstrap creates the CI roles of the other roots; the shared-services ones live here, one apply role per component of this tree.
  apply_components = sort(distinct([for f in fileset("${get_repo_root()}/infra/live/shared-services", "**/terragrunt.hcl") : basename(dirname(f))]))
  exec_account_ids = [include.envcommon.locals.env_cfg.account_id]
}
