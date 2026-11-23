locals {
  scale_sets = toset(keys(var.scale_sets))
  # Roles that may write the cache; every other role reads it.
  cache_writers = [for s, c in var.scale_sets : s if c.cache_write]

  bucket_name = "${var.name_prefix}-ci-cache-${var.account_id}"
  bucket_arn  = "arn:aws:s3:::${local.bucket_name}"
  # Role ARNs are built from names so that policies that reference them are known at plan time.
  runner_role_name = { for s in local.scale_sets : s => "${var.name_prefix}-ci-runner-${s}" }
  runner_role_arn  = { for s in local.scale_sets : s => "arn:aws:iam::${var.account_id}:role/${local.runner_role_name[s]}" }
  push_role_name   = "${var.name_prefix}-ci-ecr-push"
  eso_role_name    = "${var.name_prefix}-ci-external-secrets"
  github_subjects  = [for r in var.github_push_refs : "repo:${var.github_repository}:ref:${r}"]

  # Only the runners of the cache roles and the push role may touch cache objects; management actions stay open for Terraform.
  cache_read_actions  = ["s3:GetObject", "s3:ListBucket"]
  cache_write_actions = ["s3:PutObject"]
  cache_read_statements = [
    { Effect = "Allow", Action = local.cache_read_actions, Resource = [local.bucket_arn, "${local.bucket_arn}/*"] },
    { Effect = "Allow", Action = ["kms:Decrypt"], Resource = [aws_kms_key.cache.arn] },
  ]
  cache_write_statements = [
    { Effect = "Allow", Action = local.cache_write_actions, Resource = ["${local.bucket_arn}/*"] },
    { Effect = "Allow", Action = ["kms:GenerateDataKey"], Resource = [aws_kms_key.cache.arn] },
  ]
  ecr_pull_statements = [
    { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = ["*"] },
    { Effect = "Allow", Action = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"], Resource = var.ecr_repository_arns },
  ]
  ecr_push_statements = [
    { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = ["*"] },
    { Effect = "Allow", Action = [
      "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage",
    ], Resource = var.ecr_repository_arns },
  ]

  # What a job may do is the property of its scale set, not of a priority: cache write, image pull, plan roles; untrusted code gets an explicit deny.
  runner_policies = { for s, c in var.scale_sets : s => concat(
    local.cache_read_statements,
    c.cache_write ? local.cache_write_statements : [],
    c.ecr_pull ? local.ecr_pull_statements : [],
    c.assume_plan ? [{ Effect = "Allow", Action = ["sts:AssumeRole"], Resource = var.plan_role_arns }] : [],
    c.untrusted ? [{ Effect = "Deny", Action = ["sts:AssumeRole", "ecr:*", "secretsmanager:*"], Resource = ["*"] }] : [],
  ) }

  secret_arns = [for s in local.scale_sets : aws_secretsmanager_secret.github_app[s].arn]

  # Web-identity trust of a service account of the runner cluster.
  runner_trust = { for s in local.scale_sets : s => {
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = { StringEquals = {
        "${var.oidc_issuer}:aud" = "sts.amazonaws.com"
        "${var.oidc_issuer}:sub" = "system:serviceaccount:arc-${s}:${s}"
      } }
    }]
  } }
  eso_trust = {
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = { StringEquals = {
        "${var.oidc_issuer}:aud" = "sts.amazonaws.com"
        "${var.oidc_issuer}:sub" = "system:serviceaccount:${var.external_secrets_namespace}:${var.external_secrets_service_account}"
      } }
    }]
  }
}

resource "aws_kms_key" "cache" {
  description             = "Build cache of the CI runners"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = var.tags
}

resource "aws_kms_alias" "cache" {
  name          = "alias/${var.name_prefix}-ci-cache"
  target_key_id = aws_kms_key.cache.key_id
}

resource "aws_kms_key" "secrets" {
  description             = "GitHub App keys of the CI runner scale sets"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = var.tags
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.name_prefix}-ci-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

resource "aws_s3_bucket" "cache" {
  bucket        = local.bucket_name
  force_destroy = false
  tags          = var.tags
}

resource "aws_s3_bucket_ownership_controls" "cache" {
  bucket = aws_s3_bucket.cache.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "cache" {
  bucket                  = aws_s3_bucket.cache.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cache" {
  bucket = aws_s3_bucket.cache.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.cache.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cache" {
  bucket = aws_s3_bucket.cache.id
  rule {
    id     = "expire-cache"
    status = "Enabled"
    filter {}
    expiration {
      days = var.cache_expiration_days
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_s3_bucket_policy" "cache" {
  bucket     = aws_s3_bucket.cache.id
  depends_on = [aws_s3_bucket_public_access_block.cache]
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [local.bucket_arn, "${local.bucket_arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid       = "DenyCacheAccessOutsideRunners"
        Effect    = "Deny"
        Principal = "*"
        Action    = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource  = [local.bucket_arn, "${local.bucket_arn}/*"]
        Condition = { ArnNotLike = { "aws:PrincipalArn" = concat([for s in local.scale_sets : local.runner_role_arn[s]], [aws_iam_role.github_push.arn]) } }
      },
      {
        Sid       = "DenyCacheWritesOutsideBuildRoles"
        Effect    = "Deny"
        Principal = "*"
        Action    = ["s3:PutObject", "s3:DeleteObject"]
        Resource  = ["${local.bucket_arn}/*"]
        Condition = { ArnNotLike = { "aws:PrincipalArn" = [for w in local.cache_writers : local.runner_role_arn[w]] } }
      },
    ]
  })
}

resource "aws_secretsmanager_secret" "github_app" {
  for_each                = local.scale_sets
  name                    = "${var.name_prefix}/ci/github-app/${each.key}"
  description             = "GitHub App private key of the ${each.key} runner scale set; the value is set outside Terraform"
  kms_key_id              = aws_kms_key.secrets.arn
  recovery_window_in_days = var.secret_recovery_window_days
  tags                    = var.tags
}

resource "aws_iam_role" "runner" {
  for_each             = local.scale_sets
  name                 = local.runner_role_name[each.key]
  assume_role_policy   = jsonencode(local.runner_trust[each.key])
  permissions_boundary = var.permissions_boundary_arn
  max_session_duration = 3600
  tags                 = var.tags
}

resource "aws_iam_role_policy" "runner" {
  for_each = local.scale_sets
  name     = "runner-access"
  role     = aws_iam_role.runner[each.key].id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.runner_policies[each.key]
  })
}

resource "aws_iam_role" "github_push" {
  name                 = local.push_role_name
  permissions_boundary = var.permissions_boundary_arn
  max_session_duration = 3600
  tags                 = var.tags
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.github_oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike   = { "token.actions.githubusercontent.com:sub" = local.github_subjects }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github_push" {
  name   = "ecr-push"
  role   = aws_iam_role.github_push.id
  policy = jsonencode({ Version = "2012-10-17", Statement = local.ecr_push_statements })
}

resource "aws_iam_role" "external_secrets" {
  name                 = local.eso_role_name
  assume_role_policy   = jsonencode(local.eso_trust)
  permissions_boundary = var.permissions_boundary_arn
  max_session_duration = 3600
  tags                 = var.tags
}

resource "aws_iam_role_policy" "external_secrets" {
  name = "read-github-app-keys"
  role = aws_iam_role.external_secrets.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"], Resource = local.secret_arns },
      { Effect = "Allow", Action = ["kms:Decrypt"], Resource = [aws_kms_key.secrets.arn] },
    ]
  })
}
