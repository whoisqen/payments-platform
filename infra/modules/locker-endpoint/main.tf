locals {
  name = "${var.name_prefix}-${var.environment}-${var.region_short}-locker-endpoint"
  zone = "locker.${var.cluster_domain}"
  host = "${var.service}.${var.namespace}.svc.${local.zone}"
}

# Own subzone: the cell clusters resolve the locker host, and nothing else of cluster_domain depends on this stack.
resource "aws_route53_zone" "this" {
  # checkov:skip=CKV2_AWS_38: DNSSEC signing applies to public zones only
  # checkov:skip=CKV2_AWS_39: query logging of private zones goes through the Route 53 Resolver query log of the VPC
  name    = local.zone
  comment = "Locker of ${var.environment} ${var.region}: ${local.host}"

  vpc {
    vpc_id = var.vpc_id
  }

  tags = var.tags
}

resource "aws_security_group" "lb" {
  name        = local.name
  description = "Internal load balancer of the locker; cell nodes in, locker pods out."
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = local.name })
}

resource "aws_vpc_security_group_ingress_rule" "lb_from_cells" {
  for_each = toset(var.client_security_group_ids)

  security_group_id            = aws_security_group.lb.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  description                  = "Router and scheduler of a cell"
}

resource "aws_vpc_security_group_egress_rule" "lb_to_locker" {
  security_group_id            = aws_security_group.lb.id
  referenced_security_group_id = var.locker_pod_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  description                  = "Locker pods"
}

resource "aws_vpc_security_group_ingress_rule" "locker_from_lb" {
  security_group_id            = var.locker_pod_security_group_id
  referenced_security_group_id = aws_security_group.lb.id
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  description                  = "Locker endpoint load balancer"
}

# The mutual-TLS locker Gateway pods and the locker pods share the locker pod security group: the gateway forwards to the
# locker on the same port, so the group admits itself there.
resource "aws_vpc_security_group_ingress_rule" "locker_from_gateway" {
  security_group_id            = var.locker_pod_security_group_id
  referenced_security_group_id = var.locker_pod_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  description                  = "Locker mutual-TLS gateway to the locker pods"
}

resource "aws_lb" "this" {
  # checkov:skip=CKV_AWS_91: access logs of an NLB cover TLS listeners only; this one is TCP inside the VPC, flow logs cover it
  name                             = substr(local.name, 0, 32)
  internal                         = true
  load_balancer_type               = "network"
  subnets                          = var.subnet_ids
  security_groups                  = [aws_security_group.lb.id]
  enable_cross_zone_load_balancing = true
  enable_deletion_protection       = var.environment != "dev"
  tags                             = var.tags
}

resource "aws_lb_target_group" "this" {
  name                 = substr("${var.name_prefix}-${var.environment}-${var.region_short}-locker", 0, 32)
  port                 = var.port
  protocol             = "TCP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 60

  health_check {
    protocol            = "TCP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  tags = var.tags
}

resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.this.arn
  port              = var.port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = var.tags
}

resource "aws_route53_record" "this" {
  zone_id = aws_route53_zone.this.zone_id
  name    = local.host
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}

# The controller of the locker cluster only registers pod IPs in this target group; security groups stay with Terraform.
resource "aws_iam_role" "controller" {
  name                 = "${local.name}-controller"
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        StringEquals = { "aws:SourceAccount" = var.account_id }
        ArnEquals    = { "aws:SourceArn" = var.locker_cluster_arn }
      }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "controller" {
  name = "target-group-binding"
  role = aws_iam_role.controller.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "RegisterLockerPods", Effect = "Allow", Action = ["elasticloadbalancing:RegisterTargets", "elasticloadbalancing:DeregisterTargets"], Resource = [aws_lb_target_group.this.arn] },
      # Describe calls have no resource-level scoping.
      {
        Sid      = "Describe"
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:DescribeTargetGroups", "elasticloadbalancing:DescribeTargetHealth", "elasticloadbalancing:DescribeLoadBalancers", "elasticloadbalancing:DescribeListeners", "elasticloadbalancing:DescribeTags", "ec2:DescribeInstances", "ec2:DescribeNetworkInterfaces", "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups", "ec2:DescribeVpcs"]
        Resource = "*"
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "controller" {
  cluster_name    = var.locker_cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.controller.arn
  tags            = var.tags
}
