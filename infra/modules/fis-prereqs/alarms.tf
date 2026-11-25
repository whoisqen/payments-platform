# Burn rate and authorization rate live in Prometheus; FIS reads only CloudWatch, so the Alertmanager bridge mirrors them as one metric.
resource "aws_cloudwatch_metric_alarm" "stop_signal" {
  alarm_name          = "${local.name}-chaos-stop-slo"
  alarm_description   = "SLO burn rate 14.4 or authorization rate drop alert is firing in ${var.environment} (Alertmanager bridge)."
  namespace           = var.stop_signal.namespace
  metric_name         = var.stop_signal.metric_name
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = var.stop_signal_missing_data
  dimensions          = { Environment = var.environment }
  tags                = merge(var.tags, { Name = "${local.name}-chaos-stop-slo" })
}

# Summed over every AZ, so losing one AZ (the az-loss hypothesis) does not stop the experiment by itself.
resource "aws_cloudwatch_metric_alarm" "edge_healthy" {
  for_each = { for t in var.edge_target_groups : t.key => t }

  alarm_name          = "${local.name}-chaos-stop-edge-${each.key}"
  alarm_description   = "Payments edge ${each.key} has fewer than ${each.value.min_healthy} healthy targets for 3 min."
  namespace           = "AWS/NetworkELB"
  metric_name         = "HealthyHostCount"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  threshold           = each.value.min_healthy
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { LoadBalancer = each.value.load_balancer, TargetGroup = each.value.target_group }
  tags                = merge(var.tags, { Name = "${local.name}-chaos-stop-edge-${each.key}" })
}

# A writer emits CPUUtilization every minute; no datapoint for longer than a failover means the cluster has no writer.
resource "aws_cloudwatch_metric_alarm" "aurora_writer" {
  for_each = toset(var.aurora_cluster_ids)

  alarm_name          = "${local.name}-chaos-stop-aurora-${each.key}"
  alarm_description   = "Aurora cluster ${each.key} has had no writer for ${var.aurora_writer_minutes} min."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "SampleCount"
  period              = 60
  evaluation_periods  = var.aurora_writer_minutes
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  dimensions          = { DBClusterIdentifier = each.key, Role = "WRITER" }
  tags                = merge(var.tags, { Name = "${local.name}-chaos-stop-aurora-${each.key}" })
}

locals {
  child_alarm_names = concat(
    [aws_cloudwatch_metric_alarm.stop_signal.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.edge_healthy : a.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.aurora_writer : a.alarm_name],
    var.additional_alarm_arns,
  )
}

resource "aws_cloudwatch_composite_alarm" "chaos_stop" {
  alarm_name        = "${local.name}-chaos-stop"
  alarm_description = "Stop condition of every FIS experiment in ${var.environment}: any child alarm stops the experiment and blocks new ones."
  alarm_rule        = join(" OR ", [for a in local.child_alarm_names : "ALARM(\"${a}\")"])
  actions_enabled   = length(var.alarm_actions) > 0
  alarm_actions     = var.alarm_actions
  ok_actions        = var.alarm_actions
  tags              = merge(var.tags, { Name = "${local.name}-chaos-stop" })
}
