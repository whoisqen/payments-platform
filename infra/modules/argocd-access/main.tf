locals {
  hub          = var.mode == "hub"
  hub_role     = "${var.name_prefix}-shared-services-argocd-controller"
  hub_role_arn = "arn:aws:iam::${var.shared_services_account_id}:role/${local.hub_role}"
  writer_role  = "${var.name_prefix}-shared-services-argocd-registration"
  spoke_arns   = [for env, account in var.spoke_account_ids : "arn:aws:iam::${account}:role/${var.name_prefix}-${env}-argocd-controller"]
  secret_arns  = "arn:aws:secretsmanager:*:${var.account_id}:secret:${var.name_prefix}/argocd/clusters/*"
}

# Spoke: the role every cluster of the environment admits through its access entry; it holds no AWS rights, the access entry is the grant.
resource "aws_iam_role" "spoke" {
  count = local.hub ? 0 : 1

  name                 = "${var.name_prefix}-${var.environment}-argocd-controller"
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = local.hub_role_arn }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
  tags = var.tags
}

resource "aws_iam_role" "controller" {
  count = local.hub ? 1 : 0

  name                 = local.hub_role
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        StringEquals = { "aws:SourceAccount" = var.account_id }
        ArnEquals    = { "aws:SourceArn" = var.cluster_arn }
      }
    }]
  })
  tags = var.tags

  lifecycle {
    precondition {
      condition     = var.cluster_name != null && var.cluster_arn != null && length(var.spoke_account_ids) > 0
      error_message = "hub mode needs cluster_name, cluster_arn and spoke_account_ids."
    }
  }
}

resource "aws_iam_role_policy" "controller" {
  count = local.hub ? 1 : 0

  name = "assume-spokes"
  role = aws_iam_role.controller[0].id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Sid = "AssumeSpokeRoles", Effect = "Allow", Action = ["sts:AssumeRole", "sts:TagSession"], Resource = local.spoke_arns }]
  })
}

resource "aws_eks_pod_identity_association" "controller" {
  for_each = local.hub ? toset(var.argocd_service_accounts) : toset([])

  cluster_name    = var.cluster_name
  namespace       = var.argocd_namespace
  service_account = each.value
  role_arn        = aws_iam_role.controller[0].arn
  tags            = var.tags
}

# The eks stacks of every environment assume this role to write the cluster registration secrets.
resource "aws_iam_role" "writer" {
  count = local.hub ? 1 : 0

  name                 = local.writer_role
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = [for a in distinct(concat(values(var.spoke_account_ids), [var.account_id])) : "arn:aws:iam::${a}:root"] }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "writer" {
  count = local.hub ? 1 : 0

  name = "write-registrations"
  role = aws_iam_role.writer[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RegistrationSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:CreateSecret", "secretsmanager:DeleteSecret", "secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue", "secretsmanager:UpdateSecret", "secretsmanager:TagResource", "secretsmanager:UntagResource",
          "secretsmanager:GetResourcePolicy", "secretsmanager:PutResourcePolicy", "secretsmanager:DeleteResourcePolicy",
        ]
        Resource = local.secret_arns
      },
    ]
  })
}
