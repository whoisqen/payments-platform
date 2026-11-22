mock_provider "aws" {}

variables {
  name_prefix              = "acme"
  account_id               = "123456789012"
  permissions_boundary_arn = "arn:aws:iam::123456789012:policy/boundary"
  oidc_provider_arn        = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.eu-central-1.amazonaws.com/id/ABC"
  oidc_issuer              = "oidc.eks.eu-central-1.amazonaws.com/id/ABC"
  github_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  github_repository        = "acme/platform"
  ecr_repository_arns      = ["arn:aws:ecr:eu-central-1:123456789012:repository/payments/*"]
  plan_role_arns           = ["arn:aws:iam::333333333333:role/acme-stage-tf-plan"]
  tags                     = { team = "platform" }
}

run "one_secret_and_role_per_scale_set_without_secret_values" {
  command = plan

  assert {
    condition     = length(aws_secretsmanager_secret.github_app) == 3 && length(aws_iam_role.runner) == 3
    error_message = "each of ci-prod, ci-stage and ci-pr needs its own secret and role"
  }
  assert {
    condition     = aws_secretsmanager_secret.github_app["ci-pr"].name == "acme/ci/github-app/ci-pr"
    error_message = "the secret name must follow the name_prefix"
  }
}

run "cache_bucket_is_private_encrypted_and_expiring" {
  command = plan

  assert {
    condition     = aws_s3_bucket.cache.bucket == "acme-ci-cache-123456789012"
    error_message = "the bucket name must carry the prefix and the account"
  }
  assert {
    condition     = aws_s3_bucket_public_access_block.cache.block_public_acls && aws_s3_bucket_public_access_block.cache.restrict_public_buckets
    error_message = "the cache bucket must block public access"
  }
  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.cache.rule).expiration[0].days == 14
    error_message = "cache objects must expire after 14 days by default"
  }
}

run "push_role_trusts_only_main_and_release_refs" {
  command = plan

  assert {
    condition     = can(regex("repo:acme/platform:ref:refs/heads/main", aws_iam_role.github_push.assume_role_policy)) && can(regex("refs/heads/release/\\*", aws_iam_role.github_push.assume_role_policy))
    error_message = "the push role must be limited to main and release/* of the repository"
  }
}

run "ci_pr_role_is_denied_roles_registry_and_secrets" {
  command = apply

  assert {
    condition     = can(regex("\"Effect\":\"Deny\"", aws_iam_role_policy.runner["ci-pr"].policy)) && can(regex("secretsmanager:\\*", aws_iam_role_policy.runner["ci-pr"].policy))
    error_message = "ci-pr must carry an explicit deny of assume-role, ECR and Secrets Manager"
  }
  assert {
    condition     = !can(regex("tf-plan", aws_iam_role_policy.runner["ci-pr"].policy)) && can(regex("tf-plan", aws_iam_role_policy.runner["ci-prod"].policy))
    error_message = "only ci-prod may reach the plan roles"
  }
}

run "bad_account_id_is_rejected" {
  command = plan

  variables {
    account_id = "123"
  }

  expect_failures = [var.account_id]
}
