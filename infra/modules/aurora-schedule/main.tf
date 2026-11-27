locals {
  name     = "${var.name_prefix}-${var.env}-${var.region_short}-${var.component}"
  clusters = { for id in var.cluster_identifiers : id => "arn:aws:rds:${var.region}:${var.account_id}:cluster:${id}" }
  actions = {
    start = { cron = var.start_cron, api = "startDBCluster" }
    stop  = { cron = var.stop_cron, api = "stopDBCluster" }
  }
  schedules = merge([for id in var.cluster_identifiers : { for a, v in local.actions : "${a}-${id}" => merge(v, { cluster = id }) }]...)
}

resource "aws_scheduler_schedule_group" "this" {
  name = local.name
  tags = var.tags
}

resource "aws_iam_role" "scheduler" {
  name = local.name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = var.account_id } }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "scheduler" {
  name = "stop-start-aurora"
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["rds:StopDBCluster", "rds:StartDBCluster"]
      Resource = values(local.clusters)
    }]
  })
}

# A stopped cluster starts by itself after seven days; the weekday start keeps the window anyway.
resource "aws_scheduler_schedule" "this" {
  for_each = local.schedules

  name                         = each.key
  group_name                   = aws_scheduler_schedule_group.this.name
  schedule_expression          = each.value.cron
  schedule_expression_timezone = var.timezone
  kms_key_arn                  = var.kms_key_arn

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:rds:${each.value.api}"
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ DbClusterIdentifier = each.value.cluster })

    retry_policy {
      maximum_retry_attempts = 3
    }
  }
}
