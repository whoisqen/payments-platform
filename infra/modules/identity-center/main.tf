locals {
  # Actions that would let a person hide their own tracks or create long-lived credentials; denied to every non-Admin set.
  audit_tamper_deny = {
    Sid    = "DenyAuditTamperAndStandingCredentials"
    Effect = "Deny"
    Action = [
      "cloudtrail:DeleteTrail", "cloudtrail:StopLogging", "cloudtrail:UpdateTrail", "cloudtrail:PutEventSelectors",
      "config:DeleteConfigurationRecorder", "config:DeleteDeliveryChannel", "config:StopConfigurationRecorder",
      "guardduty:DeleteDetector", "guardduty:DisassociateFromAdministratorAccount", "guardduty:UpdateDetector",
      "securityhub:DisableSecurityHub", "logs:DeleteLogGroup", "logs:DeleteLogStream", "logs:PutRetentionPolicy",
      "iam:CreateUser", "iam:CreateAccessKey", "iam:CreateLoginProfile", "organizations:*", "account:*",
    ]
    Resource = "*"
  }

  # Data-plane reads that ReadOnlyAccess would otherwise allow; ReadOnly is for configuration, not payment data.
  data_read_deny = {
    Sid    = "DenyDataPlaneReads"
    Effect = "Deny"
    Action = [
      "s3:GetObject", "s3:GetObjectVersion", "dynamodb:GetItem", "dynamodb:BatchGetItem", "dynamodb:Query", "dynamodb:Scan",
      "dynamodb:GetRecords", "secretsmanager:GetSecretValue", "ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath",
      "kms:Decrypt", "rds-data:*", "kinesis:GetRecords", "sqs:ReceiveMessage", "kafka-cluster:ReadData",
    ]
    Resource = "*"
  }

  permission_sets = {
    "Admin" = {
      description = "Full access to the management account only (Organizations, SCP, billing)."
      session     = "PT1H"
      managed     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
      inline      = null
    }
    "PlatformAdmin" = {
      description = "Platform administration of member accounts; no audit tampering, no IAM users or keys."
      session     = "PT4H"
      managed     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
      inline      = [local.audit_tamper_deny]
    }
    (var.sre_view_permission_set) = {
      description = "View-only access for SRE in every account; EKS access entries map it to AmazonEKSViewPolicy."
      session     = "PT8H"
      managed     = ["arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"]
      inline = [{
        Sid      = "ClusterAndLogView"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster", "eks:ListClusters", "eks:AccessKubernetesApi", "logs:FilterLogEvents", "logs:GetLogEvents", "logs:StartQuery", "logs:GetQueryResults", "cloudwatch:GetMetricData"]
        Resource = "*"
      }]
    }
    "ReadOnly" = {
      description = "Read-only configuration access without data-plane reads."
      session     = "PT8H"
      managed     = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
      inline      = [local.data_read_deny]
    }
    "Billing" = {
      description = "Billing and cost management."
      session     = "PT4H"
      managed     = ["arn:aws:iam::aws:policy/job-function/Billing"]
      inline      = null
    }
    "SRE-CDE" = {
      description = "Just-in-time SRE access to CDE accounts; one hour, granted by an approved PR, never standing."
      session     = "PT1H"
      managed     = ["arn:aws:iam::aws:policy/PowerUserAccess"]
      inline      = [local.audit_tamper_deny]
    }
  }

  managed_attachments = merge([
    for ps, d in local.permission_sets : { for arn in d.managed : "${ps}/${arn}" => { permission_set = ps, arn = arn } }
  ]...)

  # SRE-View goes to every account; explicit assignments come on top, one key per account, set and group.
  standing = merge(
    merge([for a in keys(var.accounts) : { for g in var.sre_view_groups : "${a}/${var.sre_view_permission_set}/${g}" => { account = a, permission_set = var.sre_view_permission_set, group = g } }]...),
    merge(flatten([for a, sets in var.assignments : [for ps, groups in sets : { for g in groups : "${a}/${ps}/${g}" => { account = a, permission_set = ps, group = g } }]])...),
  )

  grants = { for g in var.cde_jit_grants : "${g.account}/${g.group != null ? "group" : "user"}/${coalesce(g.group, g.user)}" => g }

  # A revocation run keeps only grants that have not expired, so the apply destroys the rest.
  active_grants = { for k, g in local.grants : k => g if !var.revocation_run || timecmp(g.expires_at, plantimestamp()) > 0 }

  group_names = toset(concat([for s in values(local.standing) : s.group], [for g in values(local.active_grants) : g.group if g.group != null]))
  user_names  = toset([for g in values(local.active_grants) : g.user if g.user != null])
}

resource "aws_ssoadmin_permission_set" "this" {
  for_each = local.permission_sets

  instance_arn     = var.instance_arn
  name             = each.key
  description      = each.value.description
  session_duration = each.value.session
  tags             = var.tags
}

resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each = local.managed_attachments

  instance_arn       = var.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set].arn
  managed_policy_arn = each.value.arn
}

resource "aws_ssoadmin_permission_set_inline_policy" "this" {
  for_each = { for ps, d in local.permission_sets : ps => d.inline if d.inline != null }

  instance_arn       = var.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.key].arn
  inline_policy      = jsonencode({ Version = "2012-10-17", Statement = each.value })
}

# Okta pushes groups and users through SCIM; names are resolved here so the configuration never holds opaque ids.
data "aws_identitystore_group" "this" {
  for_each = local.group_names

  identity_store_id = var.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = each.key
    }
  }
}

data "aws_identitystore_user" "this" {
  for_each = local.user_names

  identity_store_id = var.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = each.key
    }
  }
}

resource "aws_ssoadmin_account_assignment" "standing" {
  for_each = local.standing

  instance_arn       = var.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set].arn
  principal_type     = "GROUP"
  principal_id       = data.aws_identitystore_group.this[each.value.group].group_id
  target_type        = "AWS_ACCOUNT"
  target_id          = var.accounts[each.value.account]
}

resource "aws_ssoadmin_account_assignment" "cde_jit" {
  for_each = local.active_grants

  instance_arn       = var.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this["SRE-CDE"].arn
  principal_type     = each.value.group != null ? "GROUP" : "USER"
  principal_id       = each.value.group != null ? data.aws_identitystore_group.this[each.value.group].group_id : data.aws_identitystore_user.this[each.value.user].user_id
  target_type        = "AWS_ACCOUNT"
  target_id          = var.accounts[each.value.account]

  lifecycle {
    precondition {
      condition     = timecmp(each.value.expires_at, plantimestamp()) > 0 && timecmp(each.value.expires_at, timeadd(plantimestamp(), "1h")) <= 0
      error_message = "SRE-CDE grant ${each.key} must expire in the future and at most 1 h after this plan (expires_at ${each.value.expires_at})."
    }
  }
}
