locals {
  # The shared-services run owns the account singletons; the shared-services plan role belongs to live/shared-services/eu-central-1/ci-oidc-roles.
  account_owner     = var.environment == "shared-services"
  boundary_arn      = coalesce(var.permissions_boundary_arn, "arn:aws:iam::${var.account_id}:policy/workload-boundary")
  oidc_provider_arn = "arn:aws:iam::${var.account_id}:oidc-provider/token.actions.githubusercontent.com"

  # One apply role per component of the root: the last path segment of every unit under infra/live/<root>.
  components = sort(distinct([for f in fileset("${path.module}/../live/${var.environment}", "**/terragrunt.hcl") : basename(dirname(f))]))

  cfg      = yamldecode(file("${path.module}/../../config/platform.yaml"))
  accounts = local.cfg.accounts
  # Accounts of each root, where infra/live/<root>/<region>/tf-exec creates <prefix>-<root>-tf-exec.
  root_accounts = {
    dev               = [local.accounts.dev]
    stage             = [local.accounts.stage]
    prod              = [local.accounts.prod]
    management        = [local.accounts.management]
    security          = [local.accounts.log_archive, local.accounts.audit]
    "shared-services" = [local.accounts.shared_services]
  }
  # Roots whose state the units of this root read through dependency blocks.
  dependency_roots = {
    dev        = ["shared-services"]
    stage      = ["shared-services"]
    prod       = ["shared-services"]
    management = ["security"]
    security   = ["management"]
  }
  dependency_states = [for r in lookup(local.dependency_roots, var.environment, []) : {
    bucket_arn = "arn:aws:s3:::${var.name_prefix}-${r}-euc1-tf-state-${var.account_id}"
    prefix     = r
    kms_alias  = "alias/${var.name_prefix}-${r}-euc1-tf-state"
  }]
}

module "boundary" {
  source = "../modules/permissions-boundary"
  count  = local.account_owner ? 1 : 0

  account_id = var.account_id
  tags       = var.tags
}

resource "aws_iam_openid_connect_provider" "github" {
  count = local.account_owner ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  tags           = merge(var.tags, { Name = "${var.name_prefix}-shared-services-glob-github-oidc" })
}

module "ci_roles" {
  source = "../modules/ci-oidc-roles"
  count  = local.account_owner ? 0 : 1

  account_id               = var.account_id
  environment              = var.environment
  name_prefix              = var.name_prefix
  github_repository        = var.github_repository
  create_oidc_provider     = false
  oidc_provider_arn        = local.oidc_provider_arn
  permissions_boundary_arn = local.boundary_arn
  state_bucket_arn         = aws_s3_bucket.state.arn
  state_kms_key_arn        = module.state_key.key_arn
  apply_roles              = var.apply_roles
  apply_components         = [for c in local.components : c if !contains(keys(var.apply_roles), c)]
  exec_account_ids         = local.root_accounts[var.environment]
  dependency_states        = local.dependency_states
  plan_assumable_role_arns = ["arn:aws:iam::${var.account_id}:role/${var.name_prefix}-shared-services-argocd-registration"]
  extra_assumable_role_arns = {
    "argocd-registration" = ["arn:aws:iam::${var.account_id}:role/${var.name_prefix}-shared-services-argocd-registration"]
  }
  tags = var.tags
}

moved {
  from = module.ci_roles
  to   = module.ci_roles[0]
}
