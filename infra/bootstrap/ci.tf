module "ci_roles" {
  source = "../modules/ci-oidc-roles"

  account_id               = var.account_id
  environment              = var.environment
  github_repository        = var.github_repository
  permissions_boundary_arn = var.permissions_boundary_arn
  state_bucket_arn         = aws_s3_bucket.state.arn
  state_kms_key_arn        = module.state_key.key_arn
  apply_roles              = var.apply_roles
  tags                     = var.tags
}
