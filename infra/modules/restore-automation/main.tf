data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  name       = "${var.name_prefix}-${var.env}-${var.region_short}-${var.component}"
  has_lambda = var.validator_lambda_arn != null

  publish_step = {
    name   = "publish"
    action = "aws:executeScript"
    inputs = {
      Runtime = "python3.11"
      Handler = "handler"
      Script  = file("${path.module}/restore_test.py")
      InputPayload = {
        RestoreJobId  = "{{ RestoreJobId }}"
        Status        = "{{ Status }}"
        ResourceType  = "{{ ResourceType }}"
        Namespace     = var.metric_namespace
        TargetSeconds = "{{ TargetSeconds }}"
        ValidatorArn  = var.validator_lambda_arn != null ? var.validator_lambda_arn : ""
      }
    }
  }

  document = {
    schemaVersion = "0.3"
    description   = "Measures a finished restore test job, validates the restored store and publishes duration, target and success."
    assumeRole    = "{{ AutomationAssumeRole }}"
    parameters = {
      AutomationAssumeRole = { type = "String" }
      RestoreJobId         = { type = "String" }
      Status               = { type = "String" }
      ResourceType         = { type = "String" }
      TargetSeconds        = { type = "String", default = tostring(var.target_seconds) }
    }
    mainSteps = [local.publish_step]
  }
}

resource "aws_ssm_document" "restore_test" {
  name            = local.name
  document_type   = "Automation"
  document_format = "JSON"
  content         = jsonencode(local.document)

  tags = var.tags
}

resource "aws_iam_role" "automation" {
  name = "${local.name}-automation"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ssm.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "automation" {
  name = "restore-test"
  role = aws_iam_role.automation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect   = "Allow"
          Action   = "backup:DescribeRestoreJob"
          Resource = "*"
        },
        {
          Effect    = "Allow"
          Action    = "cloudwatch:PutMetricData"
          Resource  = "*"
          Condition = { StringEquals = { "cloudwatch:namespace" = var.metric_namespace } }
        },
      ],
      local.has_lambda ? [{
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = var.validator_lambda_arn
      }] : [],
    )
  })
}

resource "aws_iam_role" "trigger" {
  name = "${local.name}-trigger"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "trigger" {
  name = "start-restore-test"
  role = aws_iam_role.trigger.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ssm:StartAutomationExecution"
        Resource = "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:automation-definition/${aws_ssm_document.restore_test.name}:*"
      },
      {
        Effect    = "Allow"
        Action    = "iam:PassRole"
        Resource  = aws_iam_role.automation.arn
        Condition = { StringEquals = { "iam:PassedToService" = "ssm.amazonaws.com" } }
      },
    ]
  })
}

# Restore test jobs end as COMPLETED or FAILED; both are measured so a failure shows as success 0.
resource "aws_cloudwatch_event_rule" "restore_finished" {
  name = local.name

  event_pattern = jsonencode({
    source        = ["aws.backup"]
    "detail-type" = ["Restore Job State Change"]
    detail = {
      status       = ["COMPLETED", "FAILED"]
      resourceType = var.resource_types
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "restore_test" {
  rule     = aws_cloudwatch_event_rule.restore_finished.name
  arn      = "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:automation-definition/${aws_ssm_document.restore_test.name}:$DEFAULT"
  role_arn = aws_iam_role.trigger.arn

  input_transformer {
    input_paths = {
      job    = "$.detail.restoreJobId"
      status = "$.detail.status"
      type   = "$.detail.resourceType"
    }
    input_template = "{\"RestoreJobId\":[\"<job>\"],\"Status\":[\"<status>\"],\"ResourceType\":[\"<type>\"],\"AutomationAssumeRole\":[\"${aws_iam_role.automation.arn}\"]}"
  }
}
