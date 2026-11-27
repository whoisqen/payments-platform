locals {
  name = "${var.name_prefix}-${var.environment}-tf-exec"
  callers = [
    "arn:aws:iam::${var.shared_services_account_id}:role/${var.name_prefix}-${var.environment}-glob-tf-plan",
    "arn:aws:iam::${var.shared_services_account_id}:role/${var.name_prefix}-${var.environment}-glob-tf-apply-*",
  ]
}

# The generated provider of every unit assumes this role; only the CI roles of the same root in shared-services may.
resource "aws_iam_role" "this" {
  name                 = local.name
  permissions_boundary = var.permissions_boundary_arn
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${var.shared_services_account_id}:root" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = { ArnLike = { "aws:PrincipalArn" = local.callers } }
    }]
  })
  tags = merge(var.tags, { Name = local.name })
}

# Terraform creates every kind of resource of the account; the boundary (where set) and the SCPs are the limits.
resource "aws_iam_role_policy_attachment" "admin" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
