locals {
  name       = "${var.name_prefix}-${var.env}-${var.region_short}-${var.component}"
  lock_table = "${var.name_prefix}-${var.env}-${var.region_short}-dr-lock"
}

data "aws_region" "current" {}

# One record per cell: only one failover run may promote it.
resource "aws_dynamodb_table" "lock" {
  name         = local.lock_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"

  attribute {
    name = "pk"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  deletion_protection_enabled = true
  tags                        = var.tags
}

resource "aws_sns_topic" "failover" {
  name              = "${local.name}-trigger"
  kms_master_key_id = "alias/aws/sns"
  tags              = var.tags
}

resource "aws_sns_topic_policy" "failover" {
  arn = aws_sns_topic.failover.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AlarmPublishes"
      Effect    = "Allow"
      Principal = { Service = "cloudwatch.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.failover.arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_cloudwatch_metric_alarm.working_region_down.arn } }
    }]
  })
}

# Route 53 publishes health check metrics in us-east-1, the standby region. Missing data does not start a failover.
resource "aws_cloudwatch_metric_alarm" "working_region_down" {
  alarm_name          = "${local.name}-working-region-down"
  alarm_description   = "The Route 53 health check of ${var.source_region} failed for ${var.alarm_evaluation_periods} minutes: promote the standby data stores"
  namespace           = "AWS/Route53"
  metric_name         = "HealthCheckStatus"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = var.alarm_evaluation_periods
  datapoints_to_alarm = var.alarm_evaluation_periods
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = concat([aws_sns_topic.failover.arn], var.notification_topic_arns)

  dimensions = {
    HealthCheckId = var.health_check_id
  }

  tags = var.tags
}

data "archive_file" "function" {
  type        = "zip"
  output_path = "${path.module}/.build/failover.zip"

  source {
    content  = file("${path.module}/../../../scripts/dr/failover.py")
    filename = "failover.py"
  }

  source {
    content  = file("${path.module}/../../../scripts/dr/lambda_handler.py")
    filename = "lambda_handler.py"
  }
}

resource "aws_cloudwatch_log_group" "function" {
  name              = "/aws/lambda/${local.name}"
  retention_in_days = 365
  tags              = var.tags
}

resource "aws_lambda_function" "failover" {
  function_name    = local.name
  role             = aws_iam_role.function.arn
  runtime          = "python3.13"
  architectures    = ["arm64"]
  handler          = "lambda_handler.handler"
  filename         = data.archive_file.function.output_path
  source_code_hash = data.archive_file.function.output_base64sha256
  timeout          = 900
  memory_size      = 256
  # One run at a time: the DynamoDB lock is the second guard.
  reserved_concurrent_executions = 1

  environment {
    variables = {
      NAME_PREFIX      = var.name_prefix
      ENVIRONMENT      = var.env
      SOURCE_REGION    = var.source_region
      TARGET_REGION    = data.aws_region.current.region
      LOCK_TABLE       = aws_dynamodb_table.lock.name
      FENCE_RULE_GROUP = var.fence_rule_group
      DENY_POLICY_ARN  = var.deny_policy_arn
      CELLS            = jsonencode(var.cells)
    }
  }

  depends_on = [aws_cloudwatch_log_group.function]
  tags       = var.tags
}

resource "aws_lambda_permission" "sns" {
  statement_id  = "AllowSnsInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.failover.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.failover.arn
}

resource "aws_sns_topic_subscription" "failover" {
  topic_arn = aws_sns_topic.failover.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.failover.arn
}

resource "aws_iam_role" "function" {
  name = "${local.name}-function"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
  tags = var.tags
}

# Least privilege: promotion of the project's global clusters, the lock table, the one deny policy and the fence rule group.
resource "aws_iam_role_policy" "function" {
  name = "failover"
  role = aws_iam_role.function.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.function.arn}:*"
      },
      {
        Sid      = "DescribeGlobalClusters"
        Effect   = "Allow"
        Action   = ["rds:DescribeGlobalClusters"]
        Resource = "*"
      },
      {
        Sid      = "PromoteAurora"
        Effect   = "Allow"
        Action   = ["rds:FailoverGlobalCluster"]
        Resource = ["arn:aws:rds::${var.account_id}:global-cluster:${var.name_prefix}-${var.env}-${var.source_region_short}-aurora-*", "arn:aws:rds:*:${var.account_id}:cluster:${var.name_prefix}-${var.env}-*-aurora-*"]
      },
      {
        Sid      = "Lock"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.lock.arn
      },
      {
        Sid      = "Fence"
        Effect   = "Allow"
        Action   = ["network-firewall:DescribeRuleGroup", "network-firewall:UpdateRuleGroup"]
        Resource = "arn:aws:network-firewall:${var.source_region}:${var.account_id}:stateful-rulegroup/${var.fence_rule_group}"
      },
      ], var.deny_policy_arn == "" ? [] : [{
        Sid      = "AllowStandbyDynamoDbWrites"
        Effect   = "Allow"
        Action   = ["iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicyVersions", "iam:CreatePolicyVersion", "iam:DeletePolicyVersion"]
        Resource = var.deny_policy_arn
    }])
  })
}
