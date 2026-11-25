locals {
  name_prefix = "${var.name_prefix}-${var.environment}-glob"
  oidc_host   = "token.actions.githubusercontent.com"
  provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : (
    var.oidc_provider_arn != null ? var.oidc_provider_arn : "arn:aws:iam::${var.account_id}:oidc-provider/${local.oidc_host}"
  )

  state_kms_statement = {
    Sid      = "StateKey"
    Effect   = "Allow"
    Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    Resource = var.state_kms_key_arn
  }

  # The subject pins repository and ref, so a fork, a pull request branch or another branch cannot assume an apply role.
  # Plan reads only and runs for pull requests and the nightly drift check on main; apply runs from main and release branches.
  trust = { for k, subs in merge(
    { plan = concat(["repo:${var.github_repository}:pull_request"], [for ref in var.plan_refs : "repo:${var.github_repository}:ref:${ref}"]) },
    { ecr-read = [for ref in var.ecr_read_refs : "repo:${var.github_repository}:ref:${ref}"] },
    { for c, r in var.apply_roles : "apply-${c}" => [for ref in var.apply_refs : "repo:${var.github_repository}:ref:${ref}"] }
    ) : k => jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = { Federated = local.provider_arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = { "${local.oidc_host}:aud" = "sts.amazonaws.com" }
          StringLike   = { "${local.oidc_host}:sub" = subs }
        }
      }]
    })
  }
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://${local.oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
  tags           = merge(var.tags, { Name = "${local.name_prefix}-github-oidc" })
}

resource "aws_iam_role" "plan" {
  name                 = "${local.name_prefix}-tf-plan"
  assume_role_policy   = local.trust["plan"]
  permissions_boundary = var.permissions_boundary_arn
  max_session_duration = 3600
  tags                 = merge(var.tags, { Name = "${local.name_prefix}-tf-plan" })
}

# Read-only describe calls need Resource "*" because the API has no resource-level scoping; state access is scoped.
resource "aws_iam_role_policy" "plan" {
  name = "plan"
  role = aws_iam_role.plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "ReadInfrastructure", Effect = "Allow", Action = var.plan_read_actions, Resource = "*" },
      { Sid = "ReadState", Effect = "Allow", Action = ["s3:GetObject", "s3:GetObjectVersion"], Resource = "${var.state_bucket_arn}/${var.environment}/*" },
      {
        Sid       = "ListState"
        Effect    = "Allow"
        Action    = "s3:ListBucket"
        Resource  = var.state_bucket_arn
        Condition = { StringLike = { "s3:prefix" = ["${var.environment}/*"] } }
      },
      { Sid = "StateLockOnly", Effect = "Allow", Action = ["s3:PutObject", "s3:DeleteObject"], Resource = "${var.state_bucket_arn}/${var.environment}/*.tflock" },
      local.state_kms_statement,
      { Sid = "NoSecretValues", Effect = "Deny", Action = ["secretsmanager:GetSecretValue", "ssm:GetParameter*"], Resource = "*" },
    ]
  })
}

resource "aws_iam_role" "apply" {
  for_each = var.apply_roles

  name                 = "${local.name_prefix}-tf-apply-${each.key}"
  assume_role_policy   = local.trust["apply-${each.key}"]
  permissions_boundary = var.permissions_boundary_arn
  max_session_duration = 3600
  tags                 = merge(var.tags, { Name = "${local.name_prefix}-tf-apply-${each.key}" })
}

resource "aws_iam_role_policy" "apply" {
  for_each = var.apply_roles

  name = "apply"
  role = aws_iam_role.apply[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        { Sid = "ComponentActions", Effect = "Allow", Action = each.value.actions, Resource = each.value.resource_arns },
        { Sid = "StateOfThisComponent", Effect = "Allow", Action = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:DeleteObject"], Resource = "${var.state_bucket_arn}/${var.environment}/${each.key}/*" },
        {
          Sid       = "ListStatePrefix"
          Effect    = "Allow"
          Action    = "s3:ListBucket"
          Resource  = var.state_bucket_arn
          Condition = { StringLike = { "s3:prefix" = ["${var.environment}/${each.key}/*"] } }
        },
        local.state_kms_statement,
        { Sid = "NoIdentityAdministration", Effect = "Deny", Action = ["iam:CreateUser", "iam:CreateAccessKey", "iam:CreateLoginProfile", "organizations:*"], Resource = "*" },
        {
          Sid       = "RolesNeedTheBoundary"
          Effect    = "Deny"
          Action    = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
          Resource  = "*"
          Condition = { StringNotEquals = { "iam:PermissionsBoundary" = var.permissions_boundary_arn } }
        },
      ],
      length(each.value.unscoped_actions) == 0 ? [] : [
        { Sid = "ActionsWithoutResourceScoping", Effect = "Allow", Action = each.value.unscoped_actions, Resource = "*" },
      ],
    )
  })
}

# Read-only registry role of the nightly digest check and the tag workflow (AWS_ROLE_ECR_READ); pushing stays with the ci-runners push role.
resource "aws_iam_role" "ecr_read" {
  count = length(var.ecr_read_repository_arns) > 0 ? 1 : 0

  name                 = "${local.name_prefix}-ecr-read"
  assume_role_policy   = local.trust["ecr-read"]
  permissions_boundary = var.permissions_boundary_arn
  max_session_duration = 3600
  tags                 = merge(var.tags, { Name = "${local.name_prefix}-ecr-read" })
}

# GetAuthorizationToken has no resource-level scoping; every image action names the repositories.
resource "aws_iam_role_policy" "ecr_read" {
  count = length(var.ecr_read_repository_arns) > 0 ? 1 : 0

  name = "ecr-read"
  role = aws_iam_role.ecr_read[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "RegistryToken", Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      {
        Sid    = "ReadImages"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer",
          "ecr:DescribeImages", "ecr:DescribeRepositories", "ecr:ListImages",
        ]
        Resource = var.ecr_read_repository_arns
      },
    ]
  })
}
