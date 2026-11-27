locals {
  base      = "${var.name_prefix}-${var.environment}-glob-runbook"
  oidc_host = "token.actions.githubusercontent.com"
  # runbook-diagnose.yml runs on main without an environment; runbook-actions.yml runs in the runbook-<env> GitHub Environment after approval.
  kinds = {
    diagnose = "repo:${var.github_repository}:ref:refs/heads/main"
    actions  = "repo:${var.github_repository}:environment:runbook-${var.environment}"
  }
  documents  = [for r in var.regions : "arn:aws:ssm:${r}:${var.account_id}:document/${var.name_prefix}-runbook-*"]
  automation = [for r in var.regions : "arn:aws:ssm:${r}:${var.account_id}:automation-definition/${var.name_prefix}-runbook-*:*"]
  executions = [for r in var.regions : "arn:aws:ssm:${r}:${var.account_id}:automation-execution/*"]
}

resource "aws_iam_role" "caller" {
  for_each = local.kinds

  name                 = "${local.base}-${each.key}"
  permissions_boundary = var.permissions_boundary_arn
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = "arn:aws:iam::${var.account_id}:oidc-provider/${local.oidc_host}" }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = { StringEquals = { "${local.oidc_host}:aud" = "sts.amazonaws.com", "${local.oidc_host}:sub" = each.value } }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "caller" {
  for_each = local.kinds

  name = "run-documents"
  role = aws_iam_role.caller[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "StartRunbookDocuments", Effect = "Allow", Action = ["ssm:StartAutomationExecution", "ssm:DescribeDocument"], Resource = concat(local.documents, local.automation) },
      { Sid = "FollowExecutions", Effect = "Allow", Action = ["ssm:GetAutomationExecution", "ssm:StopAutomationExecution", "ssm:AddTagsToResource"], Resource = concat(local.executions, local.automation) },
      {
        Sid       = "PassOwnExecRole"
        Effect    = "Allow"
        Action    = ["iam:PassRole"]
        Resource  = [aws_iam_role.exec[each.key].arn]
        Condition = { StringEquals = { "iam:PassedToService" = "ssm.amazonaws.com" } }
      },
    ]
  })
}

# The documents run as these roles (AutomationAssumeRole); diagnose reads only.
resource "aws_iam_role" "exec" {
  for_each = local.kinds

  name                 = "${local.base}-${each.key}-exec"
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ssm.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = var.account_id } }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "exec_read" {
  for_each = local.kinds

  role       = aws_iam_role.exec[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "actions" {
  for_each = toset(var.actions_exec_policy_arns)

  role       = aws_iam_role.exec["actions"].name
  policy_arn = each.value
}
