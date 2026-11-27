locals {
  policy_arn = "arn:aws:iam::${var.account_id}:policy/${var.policy_name}"
}

# A boundary caps what a role may ever do; the role's own policies grant the actual rights, so the cap is broad and the denies are the point.
resource "aws_iam_policy" "this" {
  name        = var.policy_name
  description = "Permissions boundary of every workload, cluster and CI role: no long-term credentials, no boundary escape, no audit or organization changes."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "Ceiling"
        Effect    = "Allow"
        NotAction = ["iam:CreateUser", "iam:CreateAccessKey", "iam:CreateLoginProfile", "iam:UpdateLoginProfile", "organizations:*", "account:*"]
        Resource  = "*"
      },
      {
        Sid      = "NoBoundaryTampering"
        Effect   = "Deny"
        Action   = ["iam:CreatePolicyVersion", "iam:DeletePolicy", "iam:DeletePolicyVersion", "iam:SetDefaultPolicyVersion"]
        Resource = local.policy_arn
      },
      {
        Sid      = "NoBoundaryRemoval"
        Effect   = "Deny"
        Action   = ["iam:DeleteRolePermissionsBoundary", "iam:DeleteUserPermissionsBoundary"]
        Resource = "*"
      },
      {
        Sid       = "NewRolesCarryTheBoundary"
        Effect    = "Deny"
        Action    = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
        Resource  = "*"
        Condition = { StringNotEquals = { "iam:PermissionsBoundary" = local.policy_arn } }
      },
      {
        Sid      = "NoAuditTampering"
        Effect   = "Deny"
        Action   = ["cloudtrail:StopLogging", "cloudtrail:DeleteTrail", "cloudtrail:UpdateTrail", "config:DeleteConfigurationRecorder", "config:StopConfigurationRecorder", "guardduty:DeleteDetector", "guardduty:DisassociateFromMasterAccount"]
        Resource = "*"
      },
    ]
  })

  tags = merge(var.tags, { Name = var.policy_name })
}
