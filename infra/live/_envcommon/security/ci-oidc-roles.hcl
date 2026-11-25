locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  cfg     = local.env_cfg.cfg
}

terraform {
  source = "${get_repo_root()}/infra/modules//ci-oidc-roles"
}

# Plan from pull requests and the nightly drift check on main (vars.AWS_ROLE_TF_PLAN); apply roles are added per component when the apply workflow exists.
inputs = {
  github_repository        = "${local.cfg.owner.github_org}/${local.cfg.owner.github_repo}"
  permissions_boundary_arn = local.env_cfg.permissions_boundary_arn
  state_bucket_arn         = "arn:aws:s3:::${local.cfg.naming.prefix}-${local.env_cfg.environment}-euc1-tf-state-${local.env_cfg.shared_services_account_id}"
  state_kms_key_arn        = local.env_cfg.state_kms_key_arn
  plan_refs                = ["refs/heads/main"]
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "connected"
    data-class  = "internal"
    backup-tier = "none"
  }
}
