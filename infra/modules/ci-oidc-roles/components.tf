locals {
  exec_role_arns = [for a in var.exec_account_ids : "arn:aws:iam::${a}:role/${var.name_prefix}-${var.environment}-tf-exec"]
  apply_subject  = "repo:${var.github_repository}:environment:${coalesce(var.apply_github_environment, var.environment)}"

  exec_statements = [for st in [
    { Sid = "AssumeExecRole", Effect = "Allow", Action = ["sts:AssumeRole", "sts:TagSession"], Resource = local.exec_role_arns },
  ] : st if length(local.exec_role_arns) > 0]
  plan_exec_statements = concat(local.exec_statements, local.dependency_statements, [for st in [
    { Sid = "AssumeUnitProviderRoles", Effect = "Allow", Action = ["sts:AssumeRole", "sts:TagSession"], Resource = var.plan_assumable_role_arns },
  ] : st if length(var.plan_assumable_role_arns) > 0])

  # Another root's state is read only; its key is found by alias because every root has its own key.
  dependency_statements = [for st in [
    { Sid = "ReadOtherRootState", Effect = "Allow", Action = ["s3:GetObject", "s3:GetObjectVersion"], Resource = [for d in var.dependency_states : "${d.bucket_arn}/${d.prefix}/*"] },
    { Sid = "ListOtherRootState", Effect = "Allow", Action = ["s3:ListBucket"], Resource = distinct([for d in var.dependency_states : d.bucket_arn]) },
    {
      Sid       = "DecryptOtherRootState"
      Effect    = "Allow"
      Action    = ["kms:Decrypt", "kms:DescribeKey"]
      Resource  = "*"
      Condition = { "ForAnyValue:StringEquals" = { "kms:ResourceAliases" = [for d in var.dependency_states : d.kms_alias] } }
    },
  ] : st if length(var.dependency_states) > 0]
}

# Apply roles of the components: a GitHub Environment job assumes one, it writes the state of its component only and reaches the account through the exec role.
resource "aws_iam_role" "component_apply" {
  for_each = toset(var.apply_components)

  name                 = "${local.name_prefix}-tf-apply-${each.key}"
  permissions_boundary = var.permissions_boundary_arn
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "${local.oidc_host}:aud" = "sts.amazonaws.com", "${local.oidc_host}:sub" = local.apply_subject }
      }
    }]
  })
  tags = merge(var.tags, { Name = "${local.name_prefix}-tf-apply-${each.key}" })

  lifecycle {
    precondition {
      condition     = !contains(keys(var.apply_roles), each.key)
      error_message = "a component is either in apply_roles or in apply_components."
    }
  }
}

resource "aws_iam_role_policy" "component_apply" {
  for_each = toset(var.apply_components)

  name = "apply"
  role = aws_iam_role.component_apply[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        { Sid = "StateOfThisComponent", Effect = "Allow", Action = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:DeleteObject"], Resource = ["${var.state_bucket_arn}/${var.environment}/*/${each.key}/terraform.tfstate", "${var.state_bucket_arn}/${var.environment}/*/${each.key}/terraform.tfstate.tflock"] },
        { Sid = "ReadDependencyState", Effect = "Allow", Action = ["s3:GetObject", "s3:GetObjectVersion"], Resource = "${var.state_bucket_arn}/${var.environment}/*" },
        {
          Sid       = "ListStatePrefix"
          Effect    = "Allow"
          Action    = "s3:ListBucket"
          Resource  = var.state_bucket_arn
          Condition = { StringLike = { "s3:prefix" = ["${var.environment}/*"] } }
        },
        local.state_kms_statement,
        { Sid = "NoIdentityAdministration", Effect = "Deny", Action = ["iam:CreateUser", "iam:CreateAccessKey", "iam:CreateLoginProfile", "organizations:*"], Resource = "*" },
      ],
      local.exec_statements,
      local.dependency_statements,
      [for st in [
        { Sid = "AssumeUnitProviderRole", Effect = "Allow", Action = ["sts:AssumeRole", "sts:TagSession"], Resource = lookup(var.extra_assumable_role_arns, each.key, []) },
      ] : st if length(lookup(var.extra_assumable_role_arns, each.key, [])) > 0],
    )
  })
}
