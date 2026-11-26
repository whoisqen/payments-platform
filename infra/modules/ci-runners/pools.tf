data "aws_ssm_parameter" "ami" {
  name = var.ami_ssm_parameter
}

locals {
  # Every IPv4 range except 10/8, 172.16/12, 192.168/16 and 100.64/10. A security group cannot name domains and GitHub and its storage have no stable
  # ranges, so the domain allowlist is the Network Firewall on the only route of the untrusted tier; this rule keeps out every private address.
  public_ipv4_cidrs = [
    "0.0.0.0/5", "8.0.0.0/7", "11.0.0.0/8", "12.0.0.0/6", "16.0.0.0/4", "32.0.0.0/3", "64.0.0.0/3", "96.0.0.0/6", "100.0.0.0/10",
    "100.128.0.0/9", "101.0.0.0/8", "102.0.0.0/7", "104.0.0.0/5", "112.0.0.0/4", "128.0.0.0/3", "160.0.0.0/5", "168.0.0.0/6", "172.0.0.0/12",
    "172.32.0.0/11", "172.64.0.0/10", "172.128.0.0/9", "173.0.0.0/8", "174.0.0.0/7", "176.0.0.0/4", "192.0.0.0/9", "192.128.0.0/11",
    "192.160.0.0/13", "192.169.0.0/16", "192.170.0.0/15", "192.172.0.0/14", "192.176.0.0/12", "192.192.0.0/10", "193.0.0.0/8", "194.0.0.0/7",
    "196.0.0.0/6", "200.0.0.0/5", "208.0.0.0/4", "224.0.0.0/3",
  ]
}

# Runners only call out over HTTPS (GitHub, AWS APIs, registries); nothing may connect in, and Session Manager replaces SSH.
resource "aws_security_group" "pool" {
  for_each = var.pools

  name        = local.asg_name[each.key]
  description = "CI runners of the ${each.key} pool: outbound HTTPS only"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = local.asg_name[each.key] })

  egress {
    description = each.value.untrusted ? "HTTPS to public addresses, filtered by the Network Firewall CI allowlist" : "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = each.value.untrusted ? local.public_ipv4_cidrs : ["0.0.0.0/0"]
  }

  dynamic "egress" {
    for_each = each.value.untrusted ? [var.endpoint_security_group_id] : []
    content {
      description     = "HTTPS to the interface endpoints"
      from_port       = 443
      to_port         = 443
      protocol        = "tcp"
      security_groups = [egress.value]
    }
  }
}

resource "aws_launch_template" "pool" {
  for_each = var.pools

  name          = local.asg_name[each.key]
  image_id      = data.aws_ssm_parameter.ami.value
  instance_type = each.value.instance_types[0]
  tags          = var.tags

  # An untrusted instance powers off after its one job and is replaced, so nothing a pull request left behind meets the next one.
  instance_initiated_shutdown_behavior = each.value.untrusted ? "terminate" : null

  iam_instance_profile {
    name = aws_iam_instance_profile.runner[each.key].name
  }

  # IMDSv2 with one hop: a container behind the docker bridge cannot get a token and so cannot reach the role credentials.
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
    region               = var.region
    secret_id            = aws_secretsmanager_secret.github_app[each.key].name
    asg_name             = local.asg_name[each.key]
    github_repository    = var.github_repository
    runner_version       = var.runner_version
    runner_sha256        = var.runner_sha256
    labels               = join(",", local.runner_labels[each.key])
    untrusted            = each.value.untrusted
    jit_parameter_prefix = local.jit_parameter_prefix[each.key]
  }))
}

# Pools are persistent but stateless: Spot may take an instance at any time and the group replaces it, a new image replaces all of them in turn.
resource "aws_autoscaling_group" "pool" {
  for_each = var.pools

  name                    = local.asg_name[each.key]
  min_size                = each.value.min_size
  max_size                = each.value.max_size
  vpc_zone_identifier     = each.value.untrusted ? var.untrusted_subnet_ids : var.subnet_ids
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

# An untrusted instance waits until the bootstrap function stored its JIT runner config; no config, no instance. A separate resource so it also attaches to an existing group.
resource "aws_autoscaling_lifecycle_hook" "jit_config" {
  for_each = local.untrusted_pools

  name                   = "jit-config"
  autoscaling_group_name = aws_autoscaling_group.pool[each.key].name
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_LAUNCHING"
  default_result         = "ABANDON"
  heartbeat_timeout      = 300
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
