locals {
  dr_state_buckets = var.dr_apply == null ? [] : [var.state_bucket_arn, var.dr_apply.state_replica_bucket_arn]
}

# A job of the GitHub environment presents the environment subject, so only dr-compute-<env> (required reviewers) can assume it.
resource "aws_iam_role" "dr_apply" {
  count = var.dr_apply == null ? 0 : 1

  name = "${local.name_prefix}-dr-apply"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
          "${local.oidc_host}:sub" = "repo:${var.github_repository}:environment:${var.dr_apply.github_environment}"
        }
      }
    }]
  })
  permissions_boundary = var.permissions_boundary_arn
  max_session_duration = 3600
  tags                 = merge(var.tags, { Name = "${local.name_prefix}-dr-apply" })
}

# Dependencies of the standby units read eu-central-1 outputs from the same bucket, so the role reads all of <env>/, not one unit.
resource "aws_iam_role_policy" "dr_apply" {
  count = var.dr_apply == null ? 0 : 1

  name = "dr-apply"
  role = aws_iam_role.dr_apply[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        { Sid = "StandbyActions", Effect = "Allow", Action = var.dr_apply.actions, Resource = var.dr_apply.resource_arns },
        {
          Sid      = "EnvironmentState"
          Effect   = "Allow"
          Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:DeleteObject"]
          Resource = [for b in local.dr_state_buckets : "${b}/${var.environment}/*"]
        },
        {
          Sid       = "ListEnvironmentState"
          Effect    = "Allow"
          Action    = "s3:ListBucket"
          Resource  = local.dr_state_buckets
          Condition = { StringLike = { "s3:prefix" = ["${var.environment}/*"] } }
        },
        {
          Sid      = "StateKeys"
          Effect   = "Allow"
          Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
          Resource = [var.state_kms_key_arn, var.dr_apply.state_replica_kms_key_arn]
        },
        { Sid = "NoIdentityAdministration", Effect = "Deny", Action = ["iam:CreateUser", "iam:CreateAccessKey", "iam:CreateLoginProfile", "organizations:*"], Resource = "*" },
        {
          Sid       = "RolesNeedTheBoundary"
          Effect    = "Deny"
          Action    = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
          Resource  = "*"
          Condition = { StringNotEquals = { "iam:PermissionsBoundary" = var.permissions_boundary_arn } }
        },
      ],
      length(var.dr_apply.unscoped_actions) == 0 ? [] : [
        { Sid = "ActionsWithoutResourceScoping", Effect = "Allow", Action = var.dr_apply.unscoped_actions, Resource = "*" },
      ],
    )
  })
}
