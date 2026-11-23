locals {
  pool_names = toset(keys(var.pools))
  # Pools that may write the cache; every other pool reads it.
  cache_writers = [for n, p in var.pools : n if p.cache_write]

  bucket_name = "${var.name_prefix}-ci-cache-${var.account_id}"
  bucket_arn  = "arn:aws:s3:::${local.bucket_name}"
  # Names are built from the pool, so that policies that reference them are known at plan time.
  asg_name         = { for n in local.pool_names : n => "${var.name_prefix}-ci-${n}" }
  runner_role_name = { for n in local.pool_names : n => "${var.name_prefix}-ci-runner-${n}" }
  runner_role_arn  = { for n in local.pool_names : n => "arn:aws:iam::${var.account_id}:role/${local.runner_role_name[n]}" }
  asg_arn          = { for n in local.pool_names : n => "arn:aws:autoscaling:${var.region}:${var.account_id}:autoScalingGroup:*:autoScalingGroupName/${local.asg_name[n]}" }
  push_role_name   = "${var.name_prefix}-ci-ecr-push"
  github_subjects  = [for r in var.github_push_refs : "repo:${var.github_repository}:ref:${r}"]

  # Only the roles of the cache writers and the push role may write cache objects; management actions stay open for Terraform.
  cache_read_statements = [
    { Effect = "Allow", Action = ["s3:GetObject", "s3:ListBucket"], Resource = [local.bucket_arn, "${local.bucket_arn}/*"] },
    { Effect = "Allow", Action = ["kms:Decrypt"], Resource = [aws_kms_key.cache.arn] },
  ]
  cache_write_statements = [
    { Effect = "Allow", Action = ["s3:PutObject"], Resource = ["${local.bucket_arn}/*"] },
    { Effect = "Allow", Action = ["kms:GenerateDataKey"], Resource = [aws_kms_key.cache.arn] },
  ]
  ecr_pull_statements = concat(
    [
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = ["*"] },
      { Effect = "Allow", Action = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"], Resource = var.ecr_repository_arns },
    ],
    length(var.pull_through_cache_prefixes) == 0 ? [] : [{
      Effect   = "Allow"
      Action   = ["ecr:BatchImportUpstreamImage", "ecr:CreateRepository", "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
      Resource = [for p in var.pull_through_cache_prefixes : "arn:aws:ecr:${var.region}:${var.account_id}:repository/${p}/*"]
    }],
  )
  ecr_push_statements = [
    { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = ["*"] },
    { Effect = "Allow", Action = [
      "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage",
    ], Resource = var.ecr_repository_arns },
  ]

  # What a job may do is the property of its pool: cache write, image pull, plan roles. Every instance reads its own GitHub App key to register
  # and protects itself from scale-in while a job runs; untrusted pools get an explicit deny of roles and the registry.
  pool_policies = { for n, p in var.pools : n => concat(
    local.cache_read_statements,
    p.cache_write ? local.cache_write_statements : [],
    p.ecr_pull ? local.ecr_pull_statements : [],
    p.assume_plan ? [{ Effect = "Allow", Action = ["sts:AssumeRole"], Resource = var.plan_role_arns }] : [],
    [
      { Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = [aws_secretsmanager_secret.github_app[n].arn] },
      { Effect = "Allow", Action = ["kms:Decrypt"], Resource = [aws_kms_key.secrets.arn] },
      { Effect = "Allow", Action = ["autoscaling:SetInstanceProtection"], Resource = [local.asg_arn[n]] },
    ],
    p.untrusted ? [{ Effect = "Deny", Action = ["sts:AssumeRole", "ecr:*"], Resource = ["*"] }] : [],
  ) }

  ec2_trust = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
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
  description             = "GitHub App keys of the CI runner pools"
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
        Condition = { ArnNotLike = { "aws:PrincipalArn" = concat([for n in local.pool_names : local.runner_role_arn[n]], [aws_iam_role.github_push.arn]) } }
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

# The value is JSON {"app_id": ..., "installation_id": ..., "private_key": ...} set outside Terraform; the app needs only the runner administration permission.
resource "aws_secretsmanager_secret" "github_app" {
  for_each                = local.pool_names
  name                    = "${var.name_prefix}/ci/github-app/${each.key}"
  description             = "GitHub App credentials that the instances of the ${each.key} pool register their runner with; the value is set outside Terraform"
  kms_key_id              = aws_kms_key.secrets.arn
  recovery_window_in_days = var.secret_recovery_window_days
  tags                    = var.tags
}

resource "aws_iam_role" "runner" {
  for_each             = local.pool_names
  name                 = local.runner_role_name[each.key]
  assume_role_policy   = local.ec2_trust
  permissions_boundary = var.permissions_boundary_arn
  max_session_duration = 3600
  tags                 = var.tags
}

resource "aws_iam_role_policy" "runner" {
  for_each = local.pool_names
  name     = "runner-access"
  role     = aws_iam_role.runner[each.key].id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.pool_policies[each.key]
  })
}

# Session Manager replaces SSH: no inbound port is open on any runner.
resource "aws_iam_role_policy_attachment" "ssm" {
  for_each   = local.pool_names
  role       = aws_iam_role.runner[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "runner" {
  for_each = local.pool_names
  name     = local.runner_role_name[each.key]
  role     = aws_iam_role.runner[each.key].name
  tags     = var.tags
}

# GitHub Actions on main and release branches pushes images with this role through OIDC, from whichever runner runs the job.
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
