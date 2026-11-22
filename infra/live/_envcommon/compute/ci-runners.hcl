locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "${get_repo_root()}/infra/modules//ci-runners"
}

inputs = {
  name_prefix              = local.env_cfg.cfg.storage.state_bucket_prefix
  permissions_boundary_arn = local.env_cfg.permissions_boundary_arn
  github_oidc_provider_arn = local.env_cfg.github_oidc_provider_arn
  github_repository        = local.env_cfg.github_repository
  ecr_repository_arns      = local.env_cfg.ecr_repository_arns
  plan_role_arns           = [local.env_cfg.plan_role_arn]
}
