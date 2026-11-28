locals {
  name_prefix = "${var.name_prefix}-shared"
  oidc_host   = "token.actions.githubusercontent.com"

  # The geo prefix of an inference profile id (eu., us., apac.) is not part of the foundation-model id.
  model_id           = replace(var.inference_profile_id, "/^(eu|us|apac|jp|au|us-gov|global)\\./", "")
  profile_arn        = "arn:aws:bedrock:${var.region}:${var.account_id}:inference-profile/${var.inference_profile_id}"
  foundation_arns    = [for r in var.profile_regions : "arn:aws:bedrock:${r}::foundation-model/${local.model_id}"]
  review_invoke_arns = concat([local.profile_arn], local.foundation_arns)

  invoke_actions = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
  # Log groups need the ":*" suffix in the resource of StartQuery and FilterLogEvents.
  log_group_arns = [for n in var.admin_log_group_names : "arn:aws:logs:${var.region}:${var.account_id}:log-group:${n}:*"]

  create_admin = length(var.admin_principal_arns) > 0
  admin_role   = "${local.name_prefix}-bedrock-admin-agent"
  admin_actions = concat(local.invoke_actions, [
    "logs:StartQuery", "logs:GetQueryResults", "logs:FilterLogEvents", "cloudwatch:GetMetricData",
  ], length(var.environment_role_arns) > 0 ? ["sts:AssumeRole"] : [])

  admin_trust_conditions = merge(
    { ArnLike = { "aws:PrincipalArn" = var.admin_principal_arns } },
    var.admin_require_mfa ? { Bool = { "aws:MultiFactorAuthPresent" = "true" } } : {},
    # The tag is read from the caller's principal tags (Identity Center passes IdP attributes as session tags); the assume-role request carries none.
    var.admin_principal_tag == null ? {} : { StringEquals = { "aws:PrincipalTag/${var.admin_principal_tag.key}" = var.admin_principal_tag.value } },
  )

  # Calls must name the guardrail; the identifier is the ARN with the published version.
  guardrail_identifier = "${aws_bedrock_guardrail.this.guardrail_arn}:${aws_bedrock_guardrail_version.this.version}"
  guardrail_condition  = { StringEquals = { "bedrock:GuardrailIdentifier" = local.guardrail_identifier } }

  # The ModelId dimension of AWS/Bedrock metrics is the model or inference profile id; there is no per-role dimension.
  admin_model_ids = [for a in var.admin_allowed_model_arns : element(split("/", a), length(split("/", a)) - 1)]
  alarm_model_ids = toset(concat([var.inference_profile_id], local.admin_model_ids))

  eu_regions_pattern = "eu-*"

  admin_statements = concat(
    [
      { Sid = "InvokeAllowedModels", Effect = "Allow", Action = local.invoke_actions, Resource = var.admin_allowed_model_arns, Condition = local.guardrail_condition },
      # GetQueryResults and GetMetricData have no resource-level scoping; they return only what the queries above may read.
      { Sid = "QueryResultsAndMetrics", Effect = "Allow", Action = ["logs:GetQueryResults", "cloudwatch:GetMetricData"], Resource = "*" },
    ],
    length(local.log_group_arns) == 0 ? [] : [
      { Sid = "ReadNamedLogGroups", Effect = "Allow", Action = ["logs:StartQuery", "logs:FilterLogEvents"], Resource = local.log_group_arns },
      ], length(var.environment_role_arns) == 0 ? [] : [
      # The agent reads each environment through its read-only role (admin-agent-env); no other role may be assumed
      { Sid = "AssumeEnvironmentReadRoles", Effect = "Allow", Action = ["sts:AssumeRole"], Resource = var.environment_role_arns },
      ], [
    ],
    [
      {
        Sid    = "DenyWrites"
        Effect = "Deny"
        Action = [
          "bedrock:Create*", "bedrock:Delete*", "bedrock:Put*", "bedrock:Update*", "bedrock:Start*", "bedrock:Stop*", "bedrock:Tag*", "bedrock:Untag*",
          "logs:Create*", "logs:Delete*", "logs:Put*", "logs:Update*", "logs:Associate*", "logs:Disassociate*", "logs:Tag*", "logs:Untag*",
          "cloudwatch:Put*", "cloudwatch:Delete*", "cloudwatch:Set*", "cloudwatch:Enable*", "cloudwatch:Disable*", "cloudwatch:Tag*", "cloudwatch:Untag*",
          "iam:*", "sts:AssumeRole", "s3:Put*", "s3:Delete*", "ec2:*", "eks:*", "rds:*", "lambda:*", "sns:*", "sqs:*",
        ]
        Resource = "*"
      },
      {
        Sid      = "DenySecretsAndKeys"
        Effect   = "Deny"
        Action   = ["secretsmanager:*", "ssm:GetParameter*", "kms:*"]
        Resource = "*"
      },
      # Everything not named in the allow list is refused, whatever else a later policy attaches to the role.
      { Sid = "DenyAnythingElse", Effect = "Deny", NotAction = local.admin_actions, Resource = "*" },
      # The admin agent invokes models only through the private endpoint; a call without the endpoint id in the request is refused.
      {
        Sid       = "DenyInvokeOutsideEndpoint"
        Effect    = "Deny"
        Action    = ["bedrock:Invoke*"]
        Resource  = "*"
        Condition = { StringNotEquals = { "aws:SourceVpce" = aws_vpc_endpoint.runtime.id } }
      },
    ],
    var.cde_logs_allowed ? [] : [
      {
        Sid      = "DenyCdeLogGroups"
        Effect   = "Deny"
        Action   = ["logs:*", "cloudwatch:*"]
        Resource = [for a in var.cde_account_ids : "arn:aws:logs:*:${a}:*"]
      },
    ],
    var.cde_logs_allowed ? [] : [
      # GetMetricData and the observability access manager (OAM) have no resource ARN for a metric or link, so aws:ResourceAccount is
      # matched when the service supplies it (cross-account OAM calls) and ignored otherwise. This is a backstop, not the control:
      # the control is to create no OAM link from a CDE account to the shared-services sink.
      {
        Sid       = "DenyCdeMetricsAndOam"
        Effect    = "Deny"
        Action    = ["cloudwatch:GetMetricData", "oam:*"]
        Resource  = "*"
        Condition = { StringEquals = { "aws:ResourceAccount" = var.cde_account_ids } }
      },
    ],
  )

  review_role_arn = "arn:aws:iam::${var.account_id}:role/${var.review_role_name}"
  admin_role_arn  = "arn:aws:iam::${var.account_id}:role/${local.admin_role}"
}

# CI review role: only jobs of this repository that run in the GitHub environment review_github_environment (the environment is the gate: protection rules, branch policy), only the configured profile.
resource "aws_iam_role" "review" {
  name                 = var.review_role_name
  permissions_boundary = var.permissions_boundary_arn
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.github_oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
          "${local.oidc_host}:sub" = "repo:${var.github_repository}:environment:${var.review_github_environment}"
        }
      }
    }]
  })
  tags = merge(var.tags, { Name = var.review_role_name })
}

resource "aws_iam_role_policy" "review" {
  name = "invoke-review-model"
  role = aws_iam_role.review.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "InvokeProfile", Effect = "Allow", Action = local.invoke_actions, Resource = local.profile_arn, Condition = local.guardrail_condition },
      {
        # The profile calls the foundation model on the caller's behalf; only through this profile.
        Sid       = "InvokeUnderlyingModelsViaProfile"
        Effect    = "Allow"
        Action    = local.invoke_actions
        Resource  = local.foundation_arns
        Condition = { StringLike = { "bedrock:InferenceProfileArn" = local.profile_arn }, StringEquals = local.guardrail_condition.StringEquals }
      },
    ]
  })
}

resource "aws_iam_role" "admin" {
  count = local.create_admin ? 1 : 0

  name                 = local.admin_role
  permissions_boundary = var.permissions_boundary_arn
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${var.account_id}:root" }
      Action    = "sts:AssumeRole"
      Condition = local.admin_trust_conditions
    }]
  })
  tags = merge(var.tags, { Name = local.admin_role })
}

resource "aws_iam_role_policy" "admin" {
  count = local.create_admin ? 1 : 0

  name   = "admin-agent"
  role   = aws_iam_role.admin[0].id
  policy = jsonencode({ Version = "2012-10-17", Statement = local.admin_statements })
}

# Private path: Bedrock runtime stays on the VPC; the endpoint policy admits the two roles and their models only.
resource "aws_security_group" "endpoint" {
  name        = "${local.name_prefix}-bedrock-runtime"
  description = "Bedrock runtime endpoint: 443 from the allowed CIDRs"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${local.name_prefix}-bedrock-runtime" })
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  for_each = toset(var.endpoint_allowed_cidrs)

  security_group_id = aws_security_group.endpoint.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS to the Bedrock runtime endpoint"
  tags              = var.tags
}

resource "aws_vpc_endpoint" "runtime" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.bedrock-runtime"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.endpoint.id]
  private_dns_enabled = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
        Sid       = "ReviewRole"
        Effect    = "Allow"
        Principal = { AWS = local.review_role_arn }
        Action    = local.invoke_actions
        Resource  = local.review_invoke_arns
      }],
      local.create_admin && length(var.admin_allowed_model_arns) > 0 ? [{
        Sid       = "AdminAgentRole"
        Effect    = "Allow"
        Principal = { AWS = local.admin_role_arn }
        Action    = local.invoke_actions
        Resource  = var.admin_allowed_model_arns
      }] : [],
    )
  })
  tags = merge(var.tags, { Name = "${local.name_prefix}-bedrock-runtime" })
}

# Invocation logging: absent configuration means off, so nothing is created by default.
resource "aws_s3_bucket" "invocation_logs" {
  count = var.invocation_logging_enabled ? 1 : 0

  bucket              = "${local.name_prefix}-bedrock-invocation-logs-${var.account_id}"
  object_lock_enabled = var.invocation_log_object_lock != null
  # Prompt bodies can carry cardholder-adjacent data: the bucket is connected to the CDE whatever the module tags say.
  tags = merge(var.tags, { Name = "${local.name_prefix}-bedrock-invocation-logs", "pci-scope" = "connected" })

  lifecycle {
    precondition {
      condition     = var.kms_key_arn != null
      error_message = "kms_key_arn is required when invocation_logging_enabled."
    }
    precondition {
      condition     = var.invocation_log_audit_role_arn != null && var.invocation_log_access_log_bucket != null
      error_message = "invocation_log_audit_role_arn and invocation_log_access_log_bucket are required when invocation_logging_enabled."
    }
  }
}

resource "aws_s3_bucket_versioning" "invocation_logs" {
  count = var.invocation_logging_enabled && var.invocation_log_object_lock != null ? 1 : 0

  bucket = aws_s3_bucket.invocation_logs[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "invocation_logs" {
  count = var.invocation_logging_enabled && var.invocation_log_object_lock != null ? 1 : 0

  bucket = aws_s3_bucket.invocation_logs[0].id
  rule {
    default_retention {
      mode = var.invocation_log_object_lock.mode
      days = var.invocation_log_object_lock.days
    }
  }

  depends_on = [aws_s3_bucket_versioning.invocation_logs]
}

resource "aws_s3_bucket_logging" "invocation_logs" {
  count = var.invocation_logging_enabled ? 1 : 0

  bucket        = aws_s3_bucket.invocation_logs[0].id
  target_bucket = var.invocation_log_access_log_bucket
  target_prefix = "s3-access/${aws_s3_bucket.invocation_logs[0].id}/"
}

resource "aws_s3_bucket_public_access_block" "invocation_logs" {
  count = var.invocation_logging_enabled ? 1 : 0

  bucket                  = aws_s3_bucket.invocation_logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "invocation_logs" {
  count = var.invocation_logging_enabled ? 1 : 0

  bucket = aws_s3_bucket.invocation_logs[0].id

  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "invocation_logs" {
  count = var.invocation_logging_enabled ? 1 : 0

  bucket = aws_s3_bucket.invocation_logs[0].id

  rule {
    id     = "expire"
    status = "Enabled"
    filter {}
    expiration {
      days = var.invocation_log_retention_days
    }
    dynamic "noncurrent_version_expiration" {
      for_each = var.invocation_log_object_lock == null ? [] : [1]
      content {
        noncurrent_days = var.invocation_log_retention_days
      }
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_s3_bucket_policy" "invocation_logs" {
  count = var.invocation_logging_enabled ? 1 : 0

  bucket = aws_s3_bucket.invocation_logs[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "BedrockDelivery"
        Effect    = "Allow"
        Principal = { Service = "bedrock.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.invocation_logs[0].arn}/AWSLogs/${var.account_id}/BedrockModelInvocationLogs/*"
        Condition = {
          StringEquals = { "aws:SourceAccount" = var.account_id }
          ArnLike      = { "aws:SourceArn" = "arn:aws:bedrock:${var.region}:${var.account_id}:*" }
        }
      },
      {
        # Reading the prompts is an audit act: one named role, every other principal (admins included) is refused.
        Sid       = "DenyReadExceptAuditRole"
        Effect    = "Deny"
        Principal = "*"
        Action    = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource  = "${aws_s3_bucket.invocation_logs[0].arn}/*"
        Condition = { ArnNotLike = { "aws:PrincipalArn" = var.invocation_log_audit_role_arn } }
      },
      {
        Sid       = "TlsOnly"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.invocation_logs[0].arn, "${aws_s3_bucket.invocation_logs[0].arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })
}

resource "aws_bedrock_model_invocation_logging_configuration" "this" {
  count = var.invocation_logging_enabled ? 1 : 0

  logging_config {
    text_data_delivery_enabled      = true
    image_data_delivery_enabled     = false
    embedding_data_delivery_enabled = false

    s3_config {
      bucket_name = aws_s3_bucket.invocation_logs[0].id
      key_prefix  = "AWSLogs"
    }
  }

  depends_on = [aws_s3_bucket_policy.invocation_logs]
}

# Guardrail: card numbers, CVVs and AWS access keys are blocked in prompts and answers; prompt attacks are filtered at HIGH.
resource "aws_bedrock_guardrail" "this" {
  name                      = "${local.name_prefix}-bedrock-review"
  description               = "Blocks card data and AWS keys, filters prompt attacks."
  blocked_input_messaging   = "The request was blocked by the guardrail: it contains data that must not be sent to a model."
  blocked_outputs_messaging = "The answer was blocked by the guardrail."
  tags                      = merge(var.tags, { Name = "${local.name_prefix}-bedrock-review" })

  sensitive_information_policy_config {
    dynamic "pii_entities_config" {
      for_each = ["CREDIT_DEBIT_CARD_NUMBER", "CREDIT_DEBIT_CARD_CVV", "AWS_ACCESS_KEY"]
      content {
        type          = pii_entities_config.value
        action        = "BLOCK"
        input_action  = "BLOCK"
        output_action = "BLOCK"
      }
    }
  }

  content_policy_config {
    filters_config {
      type            = "PROMPT_ATTACK"
      input_strength  = "HIGH"
      output_strength = "NONE"
    }
  }
}

# The roles are bound to a numbered version, not to DRAFT, so an edit of the guardrail does not change what callers get until the version is replaced.
resource "aws_bedrock_guardrail_version" "this" {
  guardrail_arn = aws_bedrock_guardrail.this.guardrail_arn
  description   = "Published by Terraform."
}

# Denial of wallet: the budget notifies, the alarm reacts to token volume. Neither stops calls; the hard limit is the Bedrock service quota (manual step in the README).
resource "aws_budgets_budget" "bedrock" {
  name         = "${local.name_prefix}-bedrock-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_monthly_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  tags         = merge(var.tags, { Name = "${local.name_prefix}-bedrock-monthly" })

  cost_filter {
    name   = "Service"
    values = var.budget_service_names
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    notification_type          = "ACTUAL"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = var.budget_subscriber_emails
    subscriber_sns_topic_arns  = var.budget_sns_topic_arns
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    notification_type          = "FORECASTED"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = var.budget_subscriber_emails
    subscriber_sns_topic_arns  = var.budget_sns_topic_arns
  }
}

resource "aws_cloudwatch_metric_alarm" "input_tokens" {
  for_each = local.alarm_model_ids

  alarm_name          = "${local.name_prefix}-bedrock-input-tokens-${replace(each.value, "/[^A-Za-z0-9._-]/", "-")}"
  alarm_description   = "Input tokens per hour of the model exceed the limit; a loop or a leaked role is the usual cause."
  namespace           = "AWS/Bedrock"
  metric_name         = "InputTokenCount"
  statistic           = "Sum"
  period              = 3600
  evaluation_periods  = 1
  threshold           = var.input_token_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_sns_topic_arns
  dimensions          = { ModelId = each.value }
  tags                = merge(var.tags, { Name = "${local.name_prefix}-bedrock-input-tokens" })
}
