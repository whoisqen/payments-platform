locals {
  jit_name     = "${var.name_prefix}-ci-jit-config"
  jit_role_arn = "arn:aws:iam::${var.account_id}:role/${local.jit_name}"
}

data "archive_file" "jit_config" {
  count = length(local.untrusted_pools) > 0 ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/.terraform/jit-config.zip"

  source {
    content  = file("${path.module}/functions/jit-config/index.mjs")
    filename = "index.mjs"
  }
}

resource "aws_cloudwatch_log_group" "jit_config" {
  count = length(local.untrusted_pools) > 0 ? 1 : 0

  name              = "/aws/lambda/${local.jit_name}"
  retention_in_days = 365
  tags              = var.tags
}

resource "aws_iam_role" "jit_config" {
  count = length(local.untrusted_pools) > 0 ? 1 : 0

  name                 = local.jit_name
  permissions_boundary = var.permissions_boundary_arn
  max_session_duration = 3600
  tags                 = var.tags
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = var.account_id } }
    }]
  })
}

# The only identity that holds the GitHub App keys of the untrusted pools; it hands each new instance a one-time config, never the key.
resource "aws_iam_role_policy" "jit_config" {
  count = length(local.untrusted_pools) > 0 ? 1 : 0

  name = "jit-config"
  role = aws_iam_role.jit_config[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = [for n in local.untrusted_pools : aws_secretsmanager_secret.github_app[n].arn] },
      { Effect = "Allow", Action = ["ssm:PutParameter"], Resource = [for n in local.untrusted_pools : "${local.jit_parameter_arn_prefix[n]}/*"] },
      { Effect = "Allow", Action = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"], Resource = [aws_kms_key.secrets.arn] },
      { Effect = "Allow", Action = ["autoscaling:CompleteLifecycleAction"], Resource = [for n in local.untrusted_pools : local.asg_arn[n]] },
      { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = ["${aws_cloudwatch_log_group.jit_config[0].arn}:*"] },
    ]
  })
}

# Runs outside the VPC: it needs only api.github.com and AWS APIs, and nothing in a pull request can reach it.
resource "aws_lambda_function" "jit_config" {
  count = length(local.untrusted_pools) > 0 ? 1 : 0

  function_name                  = local.jit_name
  role                           = aws_iam_role.jit_config[0].arn
  runtime                        = "nodejs22.x"
  architectures                  = ["arm64"]
  handler                        = "index.handler"
  filename                       = data.archive_file.jit_config[0].output_path
  source_code_hash               = data.archive_file.jit_config[0].output_base64sha256
  timeout                        = 60
  memory_size                    = 256
  reserved_concurrent_executions = 10

  environment {
    variables = {
      REPOSITORY      = var.github_repository
      RUNNER_GROUP_ID = tostring(var.runner_group_id)
      KMS_KEY_ID      = aws_kms_key.secrets.arn
      POOLS = jsonencode({ for n in local.untrusted_pools : local.asg_name[n] => {
        secret_id        = aws_secretsmanager_secret.github_app[n].arn
        labels           = local.runner_labels[n]
        parameter_prefix = local.jit_parameter_prefix[n]
      } })
    }
  }

  depends_on = [aws_cloudwatch_log_group.jit_config]
  tags       = var.tags
}

resource "aws_cloudwatch_event_rule" "jit_config" {
  count = length(local.untrusted_pools) > 0 ? 1 : 0

  name        = local.jit_name
  description = "Launch lifecycle actions of the untrusted CI pools"
  tags        = var.tags
  event_pattern = jsonencode({
    source        = ["aws.autoscaling"]
    "detail-type" = ["EC2 Instance-launch Lifecycle Action"]
    detail        = { AutoScalingGroupName = [for n in local.untrusted_pools : local.asg_name[n]] }
  })
}

resource "aws_cloudwatch_event_target" "jit_config" {
  count = length(local.untrusted_pools) > 0 ? 1 : 0

  rule = aws_cloudwatch_event_rule.jit_config[0].name
  arn  = aws_lambda_function.jit_config[0].arn
}

resource "aws_lambda_permission" "jit_config" {
  count = length(local.untrusted_pools) > 0 ? 1 : 0

  statement_id  = "lifecycle-events"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.jit_config[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.jit_config[0].arn
}

# Even a principal of this account with broad rights cannot read the key of an untrusted pool; only the bootstrap function can.
resource "aws_secretsmanager_secret_policy" "untrusted" {
  for_each = local.untrusted_pools

  secret_arn = aws_secretsmanager_secret.github_app[each.key].arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "OnlyTheBootstrapFunctionReads"
      Effect    = "Deny"
      Principal = "*"
      Action    = ["secretsmanager:GetSecretValue"]
      Resource  = "*"
      Condition = { ArnNotEquals = { "aws:PrincipalArn" = local.jit_role_arn } }
    }]
  })
}
