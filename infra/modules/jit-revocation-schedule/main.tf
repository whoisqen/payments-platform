locals {
  name = "${var.name_prefix}-management-euc1-cde-jit-revocation"
}

# The token never passes through Terraform: the connection is created with a placeholder and the owner sets the fine-grained
# GitHub token (Actions: write on this repository only) in the EventBridge console; Terraform ignores the value afterwards.
resource "aws_cloudwatch_event_connection" "github" {
  name               = local.name
  description        = "GitHub API, workflow_dispatch of ${var.workflow_file}"
  authorization_type = "API_KEY"

  auth_parameters {
    api_key {
      key   = "Authorization"
      value = "Bearer set-in-the-eventbridge-console"
    }
  }

  lifecycle {
    ignore_changes = [auth_parameters]
  }
}

resource "aws_cloudwatch_event_api_destination" "dispatch" {
  name                             = local.name
  description                      = "Starts ${var.workflow_file} on main."
  invocation_endpoint              = "https://api.github.com/repos/${var.github_repository}/actions/workflows/${var.workflow_file}/dispatches"
  http_method                      = "POST"
  invocation_rate_limit_per_second = 1
  connection_arn                   = aws_cloudwatch_event_connection.github.arn
}

resource "aws_cloudwatch_event_rule" "schedule" {
  name                = local.name
  description         = "Revokes expired CDE JIT grants (identity-center apply with CDE_JIT_REVOCATION_RUN=true)."
  schedule_expression = var.schedule_expression
  tags                = var.tags
}

resource "aws_iam_role" "invoke" {
  name = local.name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.schedule.arn } }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "invoke" {
  name = "invoke-dispatch"
  role = aws_iam_role.invoke.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["events:InvokeApiDestination"], Resource = [aws_cloudwatch_event_api_destination.dispatch.arn] }]
  })
}

resource "aws_sqs_queue" "dead_letter" {
  name                    = "${local.name}-dlq"
  sqs_managed_sse_enabled = true
  tags                    = var.tags
}

resource "aws_cloudwatch_event_target" "dispatch" {
  rule     = aws_cloudwatch_event_rule.schedule.name
  arn      = aws_cloudwatch_event_api_destination.dispatch.arn
  role_arn = aws_iam_role.invoke.arn
  input    = jsonencode({ ref = "main" })

  http_target {
    header_parameters = {
      Accept                 = "application/vnd.github+json"
      "X-GitHub-Api-Version" = "2022-11-28"
      "User-Agent"           = "${var.name_prefix}-cde-jit-revocation"
    }
  }

  retry_policy {
    maximum_retry_attempts       = 3
    maximum_event_age_in_seconds = 600
  }

  dead_letter_config {
    arn = aws_sqs_queue.dead_letter.arn
  }
}

resource "aws_sqs_queue_policy" "dead_letter" {
  queue_url = aws_sqs_queue.dead_letter.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.dead_letter.arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.schedule.arn } }
    }]
  })
}
