data "aws_ssm_parameter" "ami" {
  name = var.ami_ssm_parameter
}

# Runners only call out over HTTPS (GitHub, AWS APIs, registries); nothing may connect in, and Session Manager replaces SSH.
resource "aws_security_group" "pool" {
  for_each = local.pool_names

  name        = local.asg_name[each.key]
  description = "CI runners of the ${each.key} pool: outbound HTTPS only"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = local.asg_name[each.key] })

  egress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_launch_template" "pool" {
  for_each = var.pools

  name          = local.asg_name[each.key]
  image_id      = data.aws_ssm_parameter.ami.value
  instance_type = each.value.instance_types[0]
  tags          = var.tags

  iam_instance_profile {
    name = aws_iam_instance_profile.runner[each.key].name
  }

  # Containers sit one hop behind the instance and cannot reach the credentials of its role.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = each.value.root_volume_gb
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = var.ebs_kms_key_arn
      delete_on_termination = true
    }
  }

  network_interfaces {
    associate_public_ip_address = false
    delete_on_termination       = true
    security_groups             = [aws_security_group.pool[each.key].id]
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = local.asg_name[each.key], "ci-pool" = each.key })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(var.tags, { "ci-pool" = each.key })
  }

  user_data = base64encode(templatefile("${path.module}/templates/user-data.sh.tftpl", {
    region            = var.region
    secret_id         = aws_secretsmanager_secret.github_app[each.key].name
    asg_name          = local.asg_name[each.key]
    github_repository = var.github_repository
    runner_version    = var.runner_version
    runner_sha256     = var.runner_sha256
    labels            = join(",", concat(["self-hosted", "linux", "arm64", each.key], each.value.labels))
    block_metadata    = each.value.untrusted
  }))
}

# Pools are persistent but stateless: Spot may take an instance at any time and the group replaces it, a new image replaces all of them in turn.
resource "aws_autoscaling_group" "pool" {
  for_each = var.pools

  name                    = local.asg_name[each.key]
  min_size                = each.value.min_size
  max_size                = each.value.max_size
  vpc_zone_identifier     = each.value.untrusted && var.untrusted_subnet_ids != null ? var.untrusted_subnet_ids : var.subnet_ids
  capacity_rebalance      = true
  health_check_type       = "EC2"
  default_instance_warmup = 120

  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = each.value.on_demand_base
      on_demand_percentage_above_base_capacity = 0
      spot_allocation_strategy                 = "price-capacity-optimized"
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.pool[each.key].id
        version            = aws_launch_template.pool[each.key].latest_version
      }

      dynamic "override" {
        for_each = each.value.instance_types
        content {
          instance_type = override.value
        }
      }
    }
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  dynamic "tag" {
    for_each = merge(var.tags, { Name = local.asg_name[each.key], "ci-pool" = each.key })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  # The scaling policy and the schedules own the capacity after the first apply.
  lifecycle {
    ignore_changes = [desired_capacity]
  }
}

# A busy instance (one job at a time) averages high CPU, an idle one almost none; the group follows the average and busy instances are protected from scale-in.
resource "aws_autoscaling_policy" "cpu" {
  for_each = var.pools

  name                   = "${local.asg_name[each.key]}-cpu"
  autoscaling_group_name = aws_autoscaling_group.pool[each.key].name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    target_value = each.value.target_cpu

    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
  }
}

# Warm instances during working hours so that a job starts without waiting for a boot; the pool shrinks to min_size at night.
resource "aws_autoscaling_schedule" "work_start" {
  for_each = { for n, p in var.pools : n => p if p.warm_size > p.min_size }

  scheduled_action_name  = "${local.asg_name[each.key]}-work-start"
  autoscaling_group_name = aws_autoscaling_group.pool[each.key].name
  min_size               = each.value.warm_size
  max_size               = each.value.max_size
  desired_capacity       = each.value.warm_size
  recurrence             = var.work_start_cron
  time_zone              = var.time_zone
}

resource "aws_autoscaling_schedule" "work_end" {
  for_each = { for n, p in var.pools : n => p if p.warm_size > p.min_size }

  scheduled_action_name  = "${local.asg_name[each.key]}-work-end"
  autoscaling_group_name = aws_autoscaling_group.pool[each.key].name
  min_size               = each.value.min_size
  max_size               = each.value.max_size
  desired_capacity       = each.value.min_size
  recurrence             = var.work_end_cron
  time_zone              = var.time_zone
}
